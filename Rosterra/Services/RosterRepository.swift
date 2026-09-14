import Foundation
import OSLog
import Observation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import UIKit

/// The staff data layer. Mirrors the web app's Zustand `dataStore` + Firestore
/// `onSnapshot` listeners: own user doc, published shifts within the ±window,
/// own timesheets, `settings/app`, and recent messages — all live.
@MainActor
@Observable
final class RosterRepository {
    // Live state
    var currentUser: AppUser? {
        didSet { syncShiftLiveActivity() }
    }
    /// Index maintained on assignment so `shift(id:)` is O(1) instead of an
    /// O(n) first-match scan per call (list rows call it repeatedly).
    var shifts: [Shift] = [] {
        didSet {
            shiftsById = Dictionary(shifts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            reconcileClockSessionFromServerIfNeeded()
            syncShiftLiveActivity()
        }
    }
    private(set) var shiftsById: [String: Shift] = [:]
    /// Cache maintained on assignment so manager list views can resolve a
    /// timesheet-by-shift in O(1) instead of O(n) per row (O(n²) per list).
    var timesheets: [Timesheet] = [] {
        didSet {
            rebuildTimesheetIndex()
            syncShiftLiveActivity()
        }
    }
    private(set) var timesheetsByShiftId: [String: Timesheet] = [:]
    var messages: [Message] = []
    var appSettings: AppSettings = .fallback {
        didSet { syncShiftLiveActivity() }
    }
    var tasks: [RosterTask] = []
    var taskCompletions: [TaskCompletion] = []
    /// Daily Jobs (separate from Tasks): permanent manager template library
    /// (manager-only listener) + shift-scoped assignments (both roles).
    var dailyJobTemplates: [DailyJobTemplate] = []
    var dailyJobAssignments: [DailyJobAssignment] = [] {
        didSet { syncShiftLiveActivity() }
    }
    /// Per-staff "repeat these jobs daily" preferences, keyed by staffId.
    var dailyJobRepeatRules: [String: DailyJobRepeatRule] = [:]
    /// Same O(1) treatment for staff-by-id, the most common manager lookup.
    var allUsers: [AppUser] = [] {
        didSet { usersById = Dictionary(allUsers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    }
    private(set) var usersById: [String: AppUser] = [:]
    /// Manager-defined work locations (settings/locations).
    var locations: [RosterLocation] = []
    /// Roster weeks whose staff availability a manager has locked
    /// (settings/availabilityLocks → `weeks` map of weekStartKey → true).
    /// Written by "Publish & Lock"; enforced server-side by the Worker.
    var lockedAvailabilityWeeks: Set<String> = []
    // Wages module (manager-only — the `wages` collection is unreadable by
    // staff under the deployed rules, keeping earnings lines invisible to them)
    var wageAwards: [WageAward] = []
    var earningsLines: [EarningsLine] = []
    var staffWageProfiles: [StaffWageProfile] = []

    // Payroll (managers only: all payslips in a rolling window). Staff fetch
    // their own payslips one month at a time via staffPayslips(monthKey:).
    var payslips: [Payslip] = []
    private var payrollAutoGenAttempted = false

    /// Staff payslips, month-keyed ("yyyy-MM"), for the Account → Payslips
    /// filter. In-memory for the session; Firestore's persistent disk cache
    /// (unlimited, see FirebaseBootstrap) backs it across launches.
    private var staffPayslipMonthCache: [String: [Payslip]] = [:]
    /// Months confirmed against the SERVER this session (freshness gate for
    /// the current month; older months are immutable in practice).
    private var staffPayslipMonthsRefreshed: Set<String> = []

    /// Live clock-in session for the signed-in staff member (device-local;
    /// see ClockSession for why this can't be written to Firestore live).
    var clockSession: ClockSession? {
        didSet { syncShiftLiveActivity() }
    }

    /// True from the moment a Start Shift tap begins (before the GPS fix
    /// resolves) until it commits or fails. `clockSession` only becomes
    /// non-nil once that round trip finishes, and `ClockInCard.capture`
    /// awaits `LocationService.currentLocation()` first — without this flag,
    /// two different today's-shift cards each disable only their own local
    /// `isWorking` state, so both Start buttons stay tappable during that
    /// gap and a rapid double-tap (e.g. a split shift) can start two shifts
    /// concurrently. Every ClockInCard consults this in addition to its own
    /// state so the whole Today section locks together.
    var isStartingClockSession = false

    /// Verified shift attendance records (`shift_attendance` collection):
    /// server-authoritative clock-in/out timestamps + GPS fixes. Staff stream
    /// their own; managers stream all records in the shift window.
    var attendanceRecords: [ShiftAttendance] = [] {
        didSet {
            attendanceByShiftId = Dictionary(attendanceRecords.map { ($0.shiftId, $0) }, uniquingKeysWith: { first, _ in first })
            reconcileClockSessionFromServerIfNeeded()
        }
    }
    /// O(1) attendance-by-shift lookup (doc id == shiftId, so unique).
    private(set) var attendanceByShiftId: [String: ShiftAttendance] = [:]

    var isLoading = true
    var loadError: String?

    private var listeners: [ListenerRegistration] = []
    private var roleListeners: [ListenerRegistration] = []
    private var activeUID: String?
    private var pendingFirstSnapshot: Set<String> = []
    private var currentRole: UserRole? = nil
    private var roleListenersInitialized = false

    private var db: Firestore { Firestore.firestore() }
    private var storage: Storage { Storage.storage() }

    private func storageReference(for urlString: String) -> StorageReference? {
        guard let url = URL(string: urlString) else { return nil }
        return try? storage.reference(for: url)
    }

    // MARK: - Lifecycle

    func start(uid: String) {
        guard activeUID != uid else { return }
        stop()
        activeUID = uid
        loadClockSession(for: uid)
        isLoading = true
        loadError = nil
        // Include the role-specific listeners (shifts, timesheets) that every
        // role registers — otherwise isLoading clears as soon as the
        // always-on listeners arrive and the UI flashes an empty roster before
        // shifts/timesheets stream in. They start after the user doc resolves
        // the role, but Firestore always delivers an initial snapshot (even
        // empty), so markArrived will fire for them.
        pendingFirstSnapshot = ["users", "tasks", "task_completions", "shifts", "timesheets"]

        let range = BusinessRules.staffShiftDateRange()

        // users/{uid}
        listeners.append(
            db.collection("users").document(uid).addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error { self.handleError(error, label: "users"); return }
                if let data = snap?.data(), let user = AppUser(id: uid, data: data) {
                    self.currentUser = user
                    // Dynamically start shifts/timesheets queries based on roles
                    self.startRoleSpecificListeners(uid: uid, role: user.role)
                } else {
                    // No profile doc (deleted, or a signed-in Auth account
                    // whose Firestore doc never got created) or a decode
                    // failure. "shifts"/"timesheets" are only ever marked
                    // arrived from inside startRoleSpecificListeners, which
                    // never runs on this path — without this, isLoading
                    // would stay true forever with no explanation.
                    self.loadError = "We couldn't load your profile. Please sign out and back in, or contact your manager."
                    self.markArrived("shifts")
                    self.markArrived("timesheets")
                }
                self.markArrived("users")
            }
        )

        // task completions (in window)
        listeners.append(
            db.collection("task_completions")
                .whereField("date", isGreaterThanOrEqualTo: range.start)
                .whereField("date", isLessThanOrEqualTo: range.end)
                .addSnapshotListener { [weak self] snap, error in
                    guard let self else { return }
                    if let error { self.handleError(error, label: "task_completions"); return }
                    self.taskCompletions = (snap?.documents ?? []).compactMap { try? $0.data(as: TaskCompletion.self) }
                    self.markArrived("task_completions")
                }
        )

        // settings/app
        listeners.append(
            db.collection("settings").document("app").addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                if let data = snap?.data() { self.appSettings = AppSettings(data: data) }
            }
        )

        // settings/locations — manager-defined work locations
        listeners.append(
            db.collection("settings").document("locations").addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let items = snap?.data()?["items"] as? [[String: Any]] ?? []
                self.locations = items
                    .compactMap { RosterLocation(dict: $0) }
                    .sorted { $0.displayName < $1.displayName }
            }
        )

        // settings/availabilityLocks — manager-locked availability weeks
        listeners.append(
            db.collection("settings").document("availabilityLocks").addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let weeks = snap?.data()?["weeks"] as? [String: Any] ?? [:]
                // Firestore delivers booleans as NSNumber on iOS — plain
                // `as? Bool` silently drops every locked week and breaks PWA sync.
                self.lockedAvailabilityWeeks = Set(weeks.compactMap { key, value in
                    FS.bool(any: value) ? key : nil
                })
            }
        )
    }

    private func startRoleSpecificListeners(uid: String, role: UserRole) {
        guard !roleListenersInitialized || currentRole != role else { return }
        
        // Clean existing role-specific listeners
        roleListeners.forEach { $0.remove() }
        roleListeners.removeAll()
        
        roleListenersInitialized = true
        currentRole = role

        // Managers need inactive definitions too, otherwise pausing a task
        // removes the only UI capable of resuming it. Staff continue to receive
        // active tasks only.
        let taskQuery: Query
        if role == .manager {
            taskQuery = db.collection("tasks")
        } else {
            taskQuery = db.collection("tasks")
                .whereField("active", isEqualTo: true)
        }
        roleListeners.append(
            taskQuery.addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error { self.handleError(error, label: "tasks"); return }
                self.tasks = (snap?.documents ?? []).compactMap {
                    try? $0.data(as: RosterTask.self)
                }
                self.markArrived("tasks")
            }
        )

        // Photo retention sweeps (photo lifecycle — see docs/tasks-feature.md):
        // staff lose local task photos once their week ends; managers keep a
        // 90-day local review history and run the 14-day cloud backstop.
        if role == .manager {
            TaskPhotoCache.removePhotosOlderThan(days: 90)
            Task { [weak self] in
                // Give the task_completions listener a moment to deliver.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.cleanupExpiredTaskCloudPhotos()
            }
        } else {
            TaskPhotoCache.removePhotosBeforeCurrentWeek()
        }


        let range = BusinessRules.staffShiftDateRange()
        let timesheetCutoff = BusinessRules.staffTimesheetCutoff()
        let managerTimesheetCutoff = BusinessRules.managerTimesheetCutoff()
        let messageCutoff = FS.isoFormatter.string(from: RosterCalendar.addDays(-30, to: Date()))
        
        if role == .manager {
            // MANAGER LISTENERS:
            
            // 1. All shifts in date range (any staff member, published or completed)
            roleListeners.append(
                db.collection("shifts")
                    .whereField("date", isGreaterThanOrEqualTo: range.start)
                    .whereField("date", isLessThanOrEqualTo: range.end)
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleError(error, label: "shifts"); return }
                        self.shifts = (snap?.documents ?? []).compactMap { Shift(id: $0.documentID, data: $0.data()) }
                        self.markArrived("shifts")
                    }
            )
            
            // 2. Timesheets within a recent operational window (server-side
            //    filtered so the all-staff listener doesn't stream the entire
            //    collection). Every timesheet write sets `submittedAt`.
            roleListeners.append(
                db.collection("timesheets")
                    .whereField("submittedAt", isGreaterThanOrEqualTo: managerTimesheetCutoff)
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleError(error, label: "timesheets"); return }
                        self.timesheets = (snap?.documents ?? []).compactMap { Timesheet(id: $0.documentID, data: $0.data()) }
                        self.markArrived("timesheets")
                    }
            )
            
            // 3. Staff user directory (names/avatars + weekly availability).
            //    Errors must surface: a silent failure here leaves the manager
            //    looking at stale staff availability with no indication.
            roleListeners.append(
                db.collection("users")
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleError(error, label: "users"); return }
                        self.allUsers = (snap?.documents ?? []).compactMap { AppUser(id: $0.documentID, data: $0.data()) }
                    }
            )

            // 4. Shift attendance (all staff, shift window) — verified
            //    clock-in/out times and locations for the manager portal.
            roleListeners.append(
                db.collection("shift_attendance")
                    .whereField("date", isGreaterThanOrEqualTo: range.start)
                    .whereField("date", isLessThanOrEqualTo: range.end)
                    .addSnapshotListener { [weak self] snap, _ in
                        guard let self else { return }
                        self.attendanceRecords = (snap?.documents ?? [])
                            .compactMap { ShiftAttendance(id: $0.documentID, data: $0.data()) }
                    }
            )

            // Daily Job template library (permanent, manager-managed) and all
            // assignments in the shift window for live progress.
            roleListeners.append(
                db.collection("daily_job_templates")
                    .whereField("active", isEqualTo: true)
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleSecondaryError(error, label: "daily_job_templates"); return }
                        self.dailyJobTemplates = (snap?.documents ?? [])
                            .compactMap { try? $0.data(as: DailyJobTemplate.self) }
                            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    }
            )
            roleListeners.append(
                db.collection("daily_job_assignments")
                    .whereField("date", isGreaterThanOrEqualTo: range.start)
                    .whereField("date", isLessThanOrEqualTo: range.end)
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleSecondaryError(error, label: "daily_job_assignments"); return }
                        self.dailyJobAssignments = (snap?.documents ?? [])
                            .compactMap { try? $0.data(as: DailyJobAssignment.self) }
                    }
            )
            roleListeners.append(
                db.collection("daily_job_repeats")
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleSecondaryError(error, label: "daily_job_repeats"); return }
                        let rules = (snap?.documents ?? [])
                            .compactMap { try? $0.data(as: DailyJobRepeatRule.self) }
                        self.dailyJobRepeatRules = Dictionary(
                            rules.compactMap { rule in rule.id.map { ($0, rule) } },
                            uniquingKeysWith: { first, _ in first }
                        )
                    }
            )

            // 5. Wages module: awards, earnings lines, per-staff assignments —
            //    one collection, discriminated by `kind`. Manager-only by rules.
            roleListeners.append(
                db.collection("wages")
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleSecondaryError(error, label: "wages"); return }
                        let docs = snap?.documents ?? []
                        self.wageAwards = docs.compactMap { WageAward(id: $0.documentID, data: $0.data()) }
                            .sorted { $0.name < $1.name }
                        self.earningsLines = docs.compactMap { EarningsLine(id: $0.documentID, data: $0.data()) }
                            .sorted { $0.name < $1.name }
                        self.staffWageProfiles = docs.compactMap { StaffWageProfile(id: $0.documentID, data: $0.data()) }
                    }
            )

            // 6. Payroll: all payslips in a rolling window (periodStart is a
            //    yyyy-MM-dd key, so a string range query works — single-field
            //    index, no composite needed).
            let payrollCutoff = RosterCalendar.dayFormatter.string(
                from: RosterCalendar.addWeeks(-26, to: RosterCalendar.weekStart()))
            roleListeners.append(
                db.collection("payslips")
                    .whereField("periodStart", isGreaterThanOrEqualTo: payrollCutoff)
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        // Until the payslips rules block is deployed this
                        // listener is permission-denied — don't poison
                        // loadError for the rest of the manager portal.
                        if error != nil { self.payslips = []; return }
                        self.payslips = (snap?.documents ?? [])
                            .compactMap { Payslip(id: $0.documentID, data: $0.data()) }
                            .sorted { ($0.periodStart, $0.staffName) > ($1.periodStart, $1.staffName) }
                        // Weekly automatic draft generation: idempotent (only
                        // creates docs that don't exist), so kicking it from
                        // snapshot delivery is safe.
                        self.autoGeneratePayrollDraftsIfNeeded()
                    }
            )
        } else {
            // STAFF LISTENERS (Restricted to own UID):

            // Surface the location permission prompt at session start (not
            // mid-clock-in) so attendance verification is ready on first use.
            LocationService.shared.primePermission()


            // 1. Own shifts (published only)
            roleListeners.append(
                db.collection("shifts")
                    .whereField("staffId", isEqualTo: uid)
                    .whereField("status", isEqualTo: "published")
                    .whereField("date", isGreaterThanOrEqualTo: range.start)
                    .whereField("date", isLessThanOrEqualTo: range.end)
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleError(error, label: "shifts"); return }
                        self.shifts = (snap?.documents ?? []).compactMap { Shift(id: $0.documentID, data: $0.data()) }
                        self.markArrived("shifts")
                        // A persisted session whose shift no longer exists
                        // (deleted, unpublished, or aged out of the window)
                        // would silently block clock-in on every other shift
                        // — discard it.
                        if let session = self.clockSession,
                           !self.shifts.contains(where: { $0.id == session.shiftId }) {
                            self.clearClockSession()
                        }
                        // Keep local shift reminders in step with the roster.
                        self.resyncLocalShiftReminders()
                        self.resyncLocalDailyJobReminders()
                    }
            )

            // 2. Own timesheets
            roleListeners.append(
                db.collection("timesheets")
                    .whereField("staffId", isEqualTo: uid)
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleError(error, label: "timesheets"); return }
                        let all = (snap?.documents ?? []).compactMap { Timesheet(id: $0.documentID, data: $0.data()) }
                        self.timesheets = all.filter { ts in
                            guard let submitted = ts.submittedAt else { return true }
                            return submitted >= timesheetCutoff
                        }
                        self.markArrived("timesheets")
                        // Drop submit-hours locals once hours are filed.
                        self.resyncLocalShiftReminders()
                    }
            )
            
            // 3. Own attendance records (server clock-in/out confirmations)
            roleListeners.append(
                db.collection("shift_attendance")
                    .whereField("staffId", isEqualTo: uid)
                    .whereField("date", isGreaterThanOrEqualTo: range.start)
                    .whereField("date", isLessThanOrEqualTo: range.end)
                    .addSnapshotListener { [weak self] snap, _ in
                        guard let self else { return }
                        self.attendanceRecords = (snap?.documents ?? [])
                            .compactMap { ShiftAttendance(id: $0.documentID, data: $0.data()) }
                    }
            )

            // Own daily-job assignments in the shift window (drives the bell
            // badge + notification panel). Needs the (staffId, date) index.
            roleListeners.append(
                db.collection("daily_job_assignments")
                    .whereField("staffId", isEqualTo: uid)
                    .whereField("date", isGreaterThanOrEqualTo: range.start)
                    .whereField("date", isLessThanOrEqualTo: range.end)
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleSecondaryError(error, label: "daily_job_assignments"); return }
                        self.dailyJobAssignments = (snap?.documents ?? [])
                            .compactMap { try? $0.data(as: DailyJobAssignment.self) }
                        // Reschedule "check your daily jobs" reminders — this is
                        // also the trigger for repeat-daily auto-assigned jobs
                        // landing on a brand new shift, and for cancelling the
                        // rest of today's reminders once everything's completed.
                        self.resyncLocalDailyJobReminders()
                    }
            )

            // 4. Own messages (recipient, last 30 days)
            roleListeners.append(
                db.collection("messages")
                    .whereField("recipientId", isEqualTo: uid)
                    .whereField("sentAt", isGreaterThanOrEqualTo: messageCutoff)
                    .addSnapshotListener { [weak self] snap, _ in
                        guard let self else { return }
                        let msgs = (snap?.documents ?? []).compactMap { Message(id: $0.documentID, data: $0.data()) }
                        self.messages = msgs.sorted { $0.sentAt > $1.sentAt }
                    }
            )

            // 5. Payslips are deliberately NOT streamed for staff. The Account
            //    → Payslips screen fetches one month at a time on demand via
            //    staffPayslips(monthKey:) — cache-first, so previously viewed
            //    months cost zero Firestore reads (see that method).
        }
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        roleListeners.forEach { $0.remove() }
        roleListeners.removeAll()
        activeUID = nil
        currentUser = nil
        locations = []
        lockedAvailabilityWeeks = []
        shifts = []
        timesheets = []
        messages = []
        tasks = []
        taskCompletions = []
        dailyJobTemplates = []
        dailyJobAssignments = []
        allUsers = []
        wageAwards = []
        earningsLines = []
        staffWageProfiles = []
        payslips = []
        staffPayslipMonthCache = [:]
        staffPayslipMonthsRefreshed = []
        payrollAutoGenAttempted = false
        attendanceRecords = []
        roleListenersInitialized = false
        currentRole = nil
        clockSession = nil // persisted copy stays on disk for re-sign-in
        isLoading = true
    }

    /// Reconciles the Lock Screen/Dynamic Island shift card with the latest
    /// repository state. The app root also calls this on foreground entry so
    /// a system-ended activity can be restored while the shift is still live.
    func refreshShiftLiveActivity() {
        syncShiftLiveActivity()
    }

    private func syncShiftLiveActivity() {
        ShiftLiveActivityManager.sync(
            currentUser: currentUser,
            shifts: shifts,
            timesheets: timesheets,
            dailyJobs: dailyJobAssignments,
            clockSession: clockSession,
            companyName: appSettings.companyName,
            now: ServerClock.shared.now
        )
    }

    // MARK: - Clock in/out (device-local session)

    private static let clockSessionKeyPrefix = "clockSession."

    private func clockSessionKey(for uid: String) -> String {
        Self.clockSessionKeyPrefix + uid
    }

    private func loadClockSession(for uid: String) {
        guard let data = UserDefaults.standard.data(forKey: clockSessionKey(for: uid)),
              let session = try? JSONDecoder().decode(ClockSession.self, from: data),
              session.staffId == uid else {
            clockSession = nil
            return
        }
        clockSession = session
    }

    private func persistClockSession() {
        guard let uid = activeUID else { return }
        let key = clockSessionKey(for: uid)
        if let session = clockSession, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func startClockSession(shiftId: String) {
        guard let uid = activeUID, clockSession == nil else { return }
        // ServerClock, not the device clock — the unlock gate and the
        // verified ShiftAttendance record already use it; the locally
        // displayed elapsed/worked time should match rather than diverge on
        // a skewed device.
        clockSession = ClockSession(shiftId: shiftId, staffId: uid, clockInAt: ServerClock.shared.now)
        persistClockSession()
    }

    /// Repairs a lost local `ClockSession` from the server-verified
    /// attendance record instead of leaving `isClockable` free to offer
    /// Start again — which would overwrite the real `clockInAt` with a
    /// fresh one and lose the true start time from the audit trail (the
    /// local/server split has no other reconciliation point: the device
    /// local session can vanish on reinstall, device change, or a cleared
    /// `UserDefaults`, while the shift is still genuinely active server-side).
    /// Break history isn't recoverable — `ShiftAttendance` doesn't track
    /// breaks — so the rebuilt session starts with none; the user can still
    /// log/edit breaks before submitting hours.
    private func reconcileClockSessionFromServerIfNeeded() {
        guard clockSession == nil, let uid = activeUID else { return }
        let todayKey = RosterCalendar.todayKey()
        guard let activeShift = shifts.first(where: { shift in
            shift.staffId == uid &&
            shift.date == todayKey &&
            timesheet(forShift: shift.id) == nil &&
            attendanceByShiftId[shift.id]?.clockInAt != nil &&
            attendanceByShiftId[shift.id]?.clockOutAt == nil
        }), let clockInAt = attendanceByShiftId[activeShift.id]?.clockInAt else { return }
        clockSession = ClockSession(shiftId: activeShift.id, staffId: uid, clockInAt: clockInAt)
        persistClockSession()
    }

    // MARK: - Verified attendance (server timestamps + GPS)

    func attendance(forShift shiftId: String) -> ShiftAttendance? {
        attendanceByShiftId[shiftId]
    }

    /// The saved workplace matching a shift's location string, if it has
    /// geofence coordinates configured.
    func workplace(for shift: Shift) -> RosterLocation? {
        guard let name = shift.location else { return nil }
        return locations.first { $0.displayName == name && $0.hasGeofence }
    }

    /// Start the shift: local session for the live timer, plus the verified
    /// attendance record. `FieldValue.serverTimestamp()` makes the recorded
    /// time authoritative regardless of the device clock; the device clock is
    /// stored alongside it so managers can spot manipulation.
    func startShift(_ shift: Shift, fix: ShiftAttendance.Fix?) async throws {
        guard let uid = activeUID else { return }
        startClockSession(shiftId: shift.id)
        var fields: [String: Any] = [
            "shiftId": shift.id,
            "staffId": uid,
            "date": shift.date,
            "clockInAt": FieldValue.serverTimestamp(),
            "clockInDeviceAt": Timestamp(date: Date()),
        ]
        if let location = shift.location { fields["location"] = location }
        fields.merge(ShiftAttendance.fixFields(prefix: "clockIn", fix: fix)) { _, new in new }
        // Clock-in recorded: stop the "forgot to start" nag and arm the
        // end-of-shift reminder.
        ShiftReminderScheduler.cancelForgotStart(shiftId: shift.id)
        resyncLocalShiftReminders(clockedInShiftId: shift.id)
        try await db.collection("shift_attendance").document(shift.id).setData(fields, merge: true)
        Task { await WorkerAPIClient.shared.sendNotification(event: "shift-started", shiftIds: [shift.id]) }
    }

    /// End the shift: closes the local session and stamps the attendance
    /// record with the server-side clock-out time, GPS fix, and (for early
    /// leavers) the staff member's reason.
    func endShift(_ shift: Shift, fix: ShiftAttendance.Fix?, note: String? = nil,
                  useRosteredEnd: Bool = false) async throws {
        clockSession?.useRosteredEnd = useRosteredEnd
        endClockSession()
        var fields: [String: Any] = [
            "clockOutAt": FieldValue.serverTimestamp(),
            "clockOutDeviceAt": Timestamp(date: Date()),
        ]
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            fields["clockOutNote"] = String(note.prefix(500))
        }
        fields.merge(ShiftAttendance.fixFields(prefix: "clockOut", fix: fix)) { _, new in new }
        ShiftReminderScheduler.cancelForgotEnd(shiftId: shift.id)
        // Arm submit-hours local reminder (no longer clocked in).
        resyncLocalShiftReminders(clockedInShiftId: nil)
        try await db.collection("shift_attendance").document(shift.id).setData(fields, merge: true)
        Task { await WorkerAPIClient.shared.sendNotification(event: "shift-ended", shiftIds: [shift.id]) }
    }

    func startClockBreak() {
        clockSession?.startBreak(at: ServerClock.shared.now)
        persistClockSession()
    }

    func endClockBreak() {
        clockSession?.endBreak(at: ServerClock.shared.now)
        persistClockSession()
    }

    func endClockSession() {
        clockSession?.clockOut(at: ServerClock.shared.now)
        persistClockSession()
    }

    /// Discard the session (after its data lands in a timesheet, or on cancel).
    func clearClockSession() {
        clockSession = nil
        persistClockSession()
    }

    private func markArrived(_ label: String) {
        pendingFirstSnapshot.remove(label)
        if pendingFirstSnapshot.isEmpty { isLoading = false }
    }

    private func handleError(_ error: Error, label: String) {
        loadError = error.localizedDescription
        markArrived(label)
    }

    /// For listeners secondary to the core shifts/timesheets/roster data
    /// (Daily Jobs, Wages) — a transient rules/index issue on one of these
    /// shouldn't surface a generic "failed to load" error for the whole
    /// manager portal when the primary data loaded fine. Mirrors the
    /// existing precedent for the payslips listener just below. Still
    /// logged (not truly silent) so a systematic failure isn't invisible.
    private func handleSecondaryError(_ error: Error, label: String) {
        Self.log.error("\(label, privacy: .public) listener failed: \(error.localizedDescription, privacy: .public)")
        markArrived(label)
    }

    /// Force a server refresh (pull-to-refresh). Firestore listeners then
    /// reconcile. Queries mirror the active role's listeners exactly — a
    /// manager refresh previously used the staff-shaped queries and fetched
    /// nothing relevant.
    func refreshFromServer() async {
        guard let uid = activeUID else { return }
        let range = BusinessRules.staffShiftDateRange()
        do {
            if currentRole == .manager {
                async let _user = db.collection("users").document(uid).getDocument(source: .server)
                async let _shifts = db.collection("shifts")
                    .whereField("date", isGreaterThanOrEqualTo: range.start)
                    .whereField("date", isLessThanOrEqualTo: range.end)
                    .getDocuments(source: .server)
                async let _timesheets = db.collection("timesheets")
                    .whereField("submittedAt", isGreaterThanOrEqualTo: BusinessRules.managerTimesheetCutoff())
                    .getDocuments(source: .server)
                _ = try await (_user, _shifts, _timesheets)
            } else {
                async let _user = db.collection("users").document(uid).getDocument(source: .server)
                async let _shifts = db.collection("shifts")
                    .whereField("staffId", isEqualTo: uid)
                    .whereField("status", isEqualTo: "published")
                    .whereField("date", isGreaterThanOrEqualTo: range.start)
                    .whereField("date", isLessThanOrEqualTo: range.end)
                    .getDocuments(source: .server)
                async let _timesheets = db.collection("timesheets")
                    .whereField("staffId", isEqualTo: uid)
                    .getDocuments(source: .server)
                _ = try await (_user, _shifts, _timesheets)
            }
        } catch {
            // Listeners keep serving cached data, so a manual refresh failure is
            // non-critical — but log it so a systematic issue isn't invisible.
            Self.log.debug("manual refreshFromServer failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Derived lookups

    /// Shift ids whose hours/absence are already filed — used to suppress
    /// local submit-hours reminders.
    var filedTimesheetShiftIds: Set<String> {
        Set(timesheets.compactMap { ts in
            ShiftReminderScheduler.isHoursFiled(ts.status) ? ts.shiftId : nil
        })
    }

    /// Rebuild device-local shift reminders from the live roster + timesheets.
    func resyncLocalShiftReminders(clockedInShiftId: String? = nil) {
        let clocked = clockedInShiftId ?? clockSession?.shiftId
        ShiftReminderScheduler.sync(
            shifts: shifts,
            clockedInShiftId: clocked,
            filedShiftIds: filedTimesheetShiftIds
        )
    }

    /// Rebuild device-local "check your daily jobs" reminders from the live
    /// roster + assignments. See DailyJobReminderScheduler's doc comment —
    /// purely local, no server/Firebase involvement beyond the listener
    /// that was already streaming this data anyway.
    func resyncLocalDailyJobReminders() {
        DailyJobReminderScheduler.sync(shifts: shifts, assignments: dailyJobAssignments)
    }

    func timesheet(forShift shiftId: String) -> Timesheet? {
        // Fast path via the maintained index; fall back to the legacy
        // id-match only if no shiftId hit (deep-link edge case).
        timesheetsByShiftId[shiftId] ?? timesheets.first { $0.id == shiftId }
    }

    func shift(id: String) -> Shift? {
        shiftsById[id]
    }

    /// O(1) staff lookup — prefer this over `allUsers.first(where:)` in list rows.
    func user(id: String?) -> AppUser? {
        guard let id else { return nil }
        return usersById[id]
    }

    /// Keeps `timesheetsByShiftId` first-wins, matching the old `.first` scan.
    private func rebuildTimesheetIndex() {
        var index: [String: Timesheet] = [:]
        index.reserveCapacity(timesheets.count)
        for ts in timesheets where index[ts.shiftId] == nil {
            index[ts.shiftId] = ts
        }
        timesheetsByShiftId = index
    }

    /// One-shot fetch for a shift outside the live window (deep links).
    func fetchShift(id: String) async -> Shift? {
        if let local = shift(id: id) { return local }
        guard let uid = activeUID else { return nil }
        do {
            let snap = try await db.collection("shifts").document(id).getDocument()
            guard let data = snap.data(), let shift = Shift(id: snap.documentID, data: data) else { return nil }
            guard shift.staffId == uid, shift.status == .published else { return nil }
            return shift
        } catch {
            return nil
        }
    }

    var unreadMessageCount: Int {
        messages.filter { !$0.read && $0.isActive() }.count
    }

    // MARK: - Writes (mirror dataStore mutations exactly)

    private func nowISO() -> String { FS.isoFormatter.string(from: Date()) }

    /// New timesheet submission — setDoc timesheets/{shiftId}.
    func submitTimesheet(shiftId: String, staffId: String, actualStart: String, actualEnd: String,
                         breakMinutes: Int, workedHours: Double, notes: String) async throws {
        let data: [String: Any] = [
            "id": shiftId,
            "shiftId": shiftId,
            "staffId": staffId,
            "actualStart": actualStart,
            "actualEnd": actualEnd,
            "actualBreakMinutes": breakMinutes,
            "workedHours": workedHours,
            "staffNotes": notes,
            "status": TimesheetStatus.pending.rawValue,
            "submittedAt": FieldValue.serverTimestamp(),
            "updatedAt": nowISO(),
        ]
        try await db.collection("timesheets").document(shiftId).setData(data)
        ShiftReminderScheduler.cancelSubmitHours(shiftId: shiftId)
        await WorkerAPIClient.shared.sendNotification(event: "timesheet-submitted",
                                                      shiftIds: [shiftId], timesheetId: shiftId)
    }

    /// Resubmit (a previously rejected) timesheet — updateDoc, resets to pending.
    func resubmitTimesheet(id: String, actualStart: String, actualEnd: String,
                           breakMinutes: Int, workedHours: Double, notes: String) async throws {
        let data: [String: Any] = [
            "actualStart": actualStart,
            "actualEnd": actualEnd,
            "actualBreakMinutes": breakMinutes,
            "workedHours": workedHours,
            "staffNotes": notes,
            "status": TimesheetStatus.pending.rawValue,
            "rejectedReason": NSNull(),
            "submittedAt": FieldValue.serverTimestamp(),
            "updatedAt": nowISO(),
        ]
        try await db.collection("timesheets").document(id).updateData(data)
        ShiftReminderScheduler.cancelSubmitHours(shiftId: id)
        await WorkerAPIClient.shared.sendNotification(event: "timesheet-submitted",
                                                      shiftIds: [id], timesheetId: id)
    }

    /// Report an absence — creates/updates timesheets/{shiftId} with absent_reported.
    func reportAbsence(shiftId: String, staffId: String, reason: String) async throws {
        let existing = timesheet(forShift: shiftId)
        var absenceFields: [String: Any] = [
            "actualStart": "",
            "actualEnd": "",
            "actualBreakMinutes": 0,
            "workedHours": 0,
            "staffNotes": reason,
            "status": TimesheetStatus.absentReported.rawValue,
            "submittedAt": FieldValue.serverTimestamp(),
            "updatedAt": nowISO(),
        ]
        if let existing, existing.status == .rejected {
            absenceFields["rejectedReason"] = NSNull()
            try await db.collection("timesheets").document(existing.id).updateData(absenceFields)
        } else {
            absenceFields["id"] = shiftId
            absenceFields["shiftId"] = shiftId
            absenceFields["staffId"] = staffId
            try await db.collection("timesheets").document(shiftId).setData(absenceFields)
        }
        ShiftReminderScheduler.cancelSubmitHours(shiftId: shiftId)
        await WorkerAPIClient.shared.sendNotification(event: "timesheet-absent",
                                                      shiftIds: [shiftId], timesheetId: shiftId)
    }

    /// Undo a self-reported absence — deletes the timesheet.
    func undoAbsenceReport(timesheetId: String) async throws {
        try await db.collection("timesheets").document(timesheetId).delete()
    }

    /// Complete/refresh the staff profile (dob/address/phone).
    func updateProfile(dob: String, address: String, phone: String) async throws {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        try await db.collection("users").document(uid).updateData([
            "dob": dob,
            "address": address,
            "phone": phone,
            "profileUpdateRequired": false,
            "updatedAt": nowISO(),
        ])
    }

    // MARK: - Manager staff management

    /// Create a staff member: the Worker creates the Firebase Auth account
    /// (manager-authenticated endpoint), then we write users/{uid} and a
    /// CREATE_USER audit entry — mirroring the web app's addUser flow. The new
    /// user appears in `allUsers` via the existing snapshot listener. Returns
    /// the new uid.
    func createStaff(fullName: String, email: String, password: String,
                     employmentType: EmploymentType,
                     phone: String?, startDate: Date?, defaultDepartment: String? = nil) async throws -> String {
        let localId = try await WorkerAPIClient.shared.createAuthUser(email: email, password: password)
        let t = nowISO()
        var data: [String: Any] = [
            "id": localId,
            "fullName": fullName,
            "email": email,
            "phone": phone ?? "",
            "role": UserRole.staff.rawValue,
            "employmentType": employmentType.rawValue,
            "startDate": startDate.map { RosterCalendar.dayFormatter.string(from: $0) } ?? "",
            "mustChangePassword": true,
            "status": UserStatus.active.rawValue,
            "createdAt": t,
            "updatedAt": t,
        ]
        if let defaultDepartment, !defaultDepartment.isEmpty {
            data["defaultDepartment"] = defaultDepartment
        }
        do {
            try await db.collection("users").document(localId).setData(data)
        } catch {
            // The Auth account above was already created server-side. If the
            // profile write fails, that account is orphaned — a live
            // credential with no Firestore doc, invisible to the caller's
            // duplicate-email guard (which only checks synced profiles) and
            // otherwise unrecoverable from this UI. Best-effort clean it up
            // so a retry with the same email can succeed, and always surface
            // an actionable message even if the cleanup itself fails.
            await bestEffort("rollback orphaned Auth user \(localId)") {
                try await WorkerAPIClient.shared.deleteStaffUsers(staffUserIds: [localId])
            }
            throw WorkerAPIError.server(
                "Couldn't finish creating this staff member's profile, so nothing was saved. Please try again — if it keeps failing, contact support and mention the email \(email)."
            )
        }
        // Audit entry in the web client's user-management shape (NOT the
        // payroll shape) so both apps read one consistent CREATE_USER trail.
        if let actorId = currentUser?.id {
            let auditId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            await bestEffort("auditLogs CREATE_USER") { [self] in
                try await db.collection("auditLogs").document(auditId).setData([
                    "id": auditId,
                    "actorUserId": actorId,
                    "action": "CREATE_USER",
                    "entityType": "user",
                    "entityId": localId,
                    "createdAt": nowISO(),
                ])
            }
        }
        return localId
    }

    /// Update one or more fields on a staff member's record — only the provided
    /// keys are written (per-field edits), plus `updatedAt`. Requires Firestore
    /// rules that permit manager writes to user documents (same elevated access
    /// managers use for shifts/timesheets). Email is NOT edited here — it is a
    /// sign-in credential, so the manager uses `requestStaffEmailChange` and the
    /// staff member changes their own email via Firebase's verified flow.
    func updateStaffFields(staffId: String, _ fields: [String: Any]) async throws {
        guard !fields.isEmpty else { return }
        var data = fields
        data["updatedAt"] = nowISO()
        try await db.collection("users").document(staffId).updateData(data)
    }

    /// Schedule ATO-safe account deletion (lock + 30-day Auth purge). Keeps
    /// timesheets, shifts, payslips, and identity fields.
    func approveStaffAccountDeletion(staffId: String) async throws {
        try await WorkerAPIClient.shared.approveAccountDeletion(staffUserId: staffId)
        await refreshFromServer()
    }

    func declineStaffAccountDeletion(staffId: String) async throws {
        try await WorkerAPIClient.shared.declineAccountDeletion(staffUserId: staffId)
        await refreshFromServer()
    }

    func cancelStaffAccountDeletion(staffId: String) async throws {
        try await WorkerAPIClient.shared.cancelAccountDeletion(staffUserId: staffId)
        await refreshFromServer()
    }

    func requestOwnAccountDeletion() async throws {
        try await WorkerAPIClient.shared.requestAccountDeletion(via: "ios")
        await refreshFromServer()
    }

    /// Prompt a staff member to change their own sign-in email. Sets a flag on
    /// their user doc; the staff app shows a banner and they complete the change
    /// themselves via Firebase's verified flow (only the user can change their
    /// own Auth email securely). Manager cannot set another user's Auth email.
    func requestStaffEmailChange(staffId: String) async throws {
        try await db.collection("users").document(staffId).updateData([
            "emailChangeRequired": true,
            "updatedAt": nowISO(),
        ])
    }

    /// Cancel a pending email-change request.
    func cancelStaffEmailChange(staffId: String) async throws {
        try await db.collection("users").document(staffId).updateData([
            "emailChangeRequired": false,
            "updatedAt": nowISO(),
        ])
    }

    /// Manager requires a staff member to re-enter their address. Clears the
    /// stored address and sets `profileUpdateRequired`, so on the staff's next
    /// launch the ProfileCompletionView gate forces a new address (or sign out).
    func requestStaffAddressUpdate(staffId: String) async throws {
        try await db.collection("users").document(staffId).updateData([
            "address": "",
            "profileUpdateRequired": true,
            "updatedAt": nowISO(),
        ])
    }

    /// Save the full weekly availability map via the Worker (trusted week lock),
    /// then optimistically update the local profile. Mirrors saveWeeklyAvailability.
    func saveWeeklyAvailability(_ weekly: [String: UserAvailability]) async throws {
        guard let user = currentUser else { throw AuthError.notAuthenticated }
        try await WorkerAPIClient.shared.saveAvailability(userId: user.id, weeklyAvailability: weekly)
        var updated = user
        updated.weeklyAvailability = weekly
        currentUser = updated
    }

    // MARK: - Best-effort background writes

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.surainvestments.roster",
        category: "RosterRepository"
    )

    /// Run a non-critical Firestore/Storage write that must never surface an
    /// error to the user, but should not fail *silently* either — a systematic
    /// failure (rules/index regression) is otherwise invisible.
    private func bestEffort(_ label: String, _ op: () async throws -> Void) async {
        do { try await op() }
        catch { Self.log.error("bestEffort \(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)") }
    }

    func markMessageRead(_ id: String) async {
        await bestEffort("markMessageRead") {
            try await db.collection("messages").document(id).updateData(["read": true])
        }
    }

    func markMessagesRead(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        let batch = db.batch()
        for id in ids {
            batch.updateData(["read": true], forDocument: db.collection("messages").document(id))
        }
        await bestEffort("markMessagesRead") { try await batch.commit() }
    }

    /// Photos allowed per completion — each is ≤ 2 MB, so this caps a single
    /// completion's Storage footprint at ~8 MB until review/cleanup.
    static let maxPhotosPerCompletion = 4

    /// Complete a task for a given date. Photos are compressed to fit the
    /// 2 MB Storage budget, uploaded, and cached in the app sandbox (never
    /// the phone gallery).
    func completeTask(taskId: String, date: String, images: [UIImage], note: String? = nil) async throws {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        var photoUrls: [String] = []

        for (index, image) in images.prefix(Self.maxPhotosPerCompletion).enumerated() {
            guard let data = ImageCompressor.jpegData(from: image) else {
                throw NSError(domain: "RosterRepository", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
            }
            let storageRef = storage.reference().child("task_photos/\(uid)/\(taskId)_\(date)_\(UUID().uuidString).jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            metadata.customMetadata = [
                "owner": uid,
                "taskId": taskId,
                "date": date
            ]

            _ = try await storageRef.putDataAsync(data, metadata: metadata)
            photoUrls.append(storageRef.description)

            TaskPhotoCache.save(image: image, taskId: taskId, date: date, index: index)
        }

        // setData (not merge) intentionally resets any prior redo state —
        // a resubmission replaces the old completion outright.
        let docId = "\(taskId)_\(date)"
        var completionData: [String: Any] = [
            "id": docId,
            "taskId": taskId,
            "date": date,
            "completed": true,
            "status": "completed",
            "completedAt": FieldValue.serverTimestamp(),
            "completedBy": uid,
            // First photo mirrored to the legacy field for PWA compatibility.
            "staffPhotoUrl": photoUrls.first ?? NSNull(),
            "staffPhotoUrls": photoUrls.isEmpty ? NSNull() : photoUrls
        ]
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completionData["note"] = note
        }
        try await db.collection("task_completions").document(docId).setData(completionData)
        Task { await WorkerAPIClient.shared.sendNotification(event: "task-completed") }
    }

    /// Download all verification photos once and save them in the app
    /// sandbox; afterwards they are always served locally. When a manager
    /// triggers the first download, stamp `managerDownloadedAt` — the 14-day
    /// cloud cleanup clock starts from that moment.
    func downloadAndCachePhotos(taskId: String, date: String, urlStrings: [String]) async -> [UIImage] {
        var images: [UIImage] = []
        for (index, urlString) in urlStrings.enumerated() {
            guard let image = await fetchPhoto(urlString) else { continue }
            TaskPhotoCache.save(image: image, taskId: taskId, date: date, index: index)
            images.append(image)
        }
        guard !images.isEmpty else { return [] }

        if currentUser?.role == .manager {
            let docId = "\(taskId)_\(date)"
            if let comp = taskCompletions.first(where: { $0.id == docId }), comp.managerDownloadedAt == nil {
                await bestEffort("stampManagerDownloadedAt") {
                    try await db.collection("task_completions").document(docId)
                        .updateData(["managerDownloadedAt": FieldValue.serverTimestamp()])
                }
            }
        }
        return images
    }

    private func fetchPhoto(_ urlString: String) async -> UIImage? {
        if urlString.hasPrefix("gs://") {
            guard let ref = storageReference(for: urlString),
                  let data = try? await ref.data(maxSize: Int64(ImageCompressor.maxBytes)) else { return nil }
            return UIImage(data: data)
        }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Daily Jobs (separate from Tasks — see docs/daily-jobs-feature.md)

    /// Add a reusable job to the permanent template library.
    func addDailyJobTemplate(title: String) async throws {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        try await db.collection("daily_job_templates").document().setData([
            "title": title,
            "active": true,
            "createdAt": FieldValue.serverTimestamp(),
            "createdBy": uid
        ])
    }

    /// Remove a job from the template library. Existing shift assignments keep
    /// their snapshotted title/history — only the reusable library entry goes.
    func deleteDailyJobTemplate(id: String) async throws {
        try await db.collection("daily_job_templates").document(id).delete()
    }

    /// Rename a job in the template library. Existing shift assignments keep
    /// their already-snapshotted title (same "history never rewrites" rule as
    /// delete) — only future assignments of this template pick up the new name.
    func renameDailyJobTemplate(id: String, title: String) async throws {
        try await db.collection("daily_job_templates").document(id).updateData(["title": title])
    }

    /// Replace a shift's job assignments with the given template selection,
    /// in `templateIds`' order — callers pass an already-ordered array (not a
    /// Set: Swift's Set has no defined iteration order, which previously made
    /// a newly-created day's job order essentially random instead of
    /// following whatever the manager last arranged). Deterministic doc IDs
    /// make re-saving idempotent; deselected jobs are removed, already-
    /// assigned jobs keep their completion state.
    func setDailyJobs(for shift: Shift, templateIds: [String]) async throws {
        let existing = dailyJobAssignments.filter { $0.shiftId == shift.id }
        let addedAny = try await applyDailyJobs(
            shiftId: shift.id, staffId: shift.staffId, date: shift.date,
            templateIds: templateIds, existing: existing
        )
        if addedAny {
            let staffId = shift.staffId
            Task { await WorkerAPIClient.shared.sendNotification(event: "job-assigned", recipientIds: [staffId]) }
        }
    }

    /// Shared batch-write behind `setDailyJobs` and the new-shift auto-repeat
    /// hook in `saveShift` — same idempotent diff-against-`existing` logic
    /// either way. Returns whether any assignment was newly added.
    @discardableResult
    private func applyDailyJobs(
        shiftId: String, staffId: String, date: String,
        templateIds: [String], existing: [DailyJobAssignment]
    ) async throws -> Bool {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        let batch = db.batch()

        for assignment in existing where !templateIds.contains(assignment.templateId) {
            batch.deleteDocument(db.collection("daily_job_assignments").document(assignment.id))
        }
        var addedAny = false
        // New assignments are appended after whatever's already ordered —
        // arranging them relative to each other is what drag-reorder is for.
        var nextOrder = (existing.compactMap(\.order).max() ?? -1) + 1
        for templateId in templateIds {
            guard !existing.contains(where: { $0.templateId == templateId }),
                  let template = dailyJobTemplates.first(where: { $0.id == templateId }) else { continue }
            let docId = DailyJobAssignment.docId(shiftId: shiftId, templateId: templateId)
            batch.setData([
                "id": docId,
                "shiftId": shiftId,
                "staffId": staffId,
                "templateId": templateId,
                "title": template.title,
                "date": date,
                "order": nextOrder,
                "assignedAt": FieldValue.serverTimestamp(),
                "assignedBy": uid,
                "completed": false
            ], forDocument: db.collection("daily_job_assignments").document(docId))
            nextOrder += 1
            addedAny = true
        }
        try await batch.commit()
        return addedAny
    }

    /// Persist a manager's drag-to-reorder of one shift's job assignments —
    /// staff then work through the jobs on their end in this exact order.
    /// Also refreshes this staff member's repeat rule (if one exists) to the
    /// same order, best-effort — otherwise a drag done AFTER the initial Save
    /// (the common case: assign, then reorder) would never be reflected in
    /// tomorrow's auto-repeated jobs, which is exactly the bug this fixes.
    func reorderDailyJobs(orderedAssignmentIds: [String], staffId: String) async throws {
        let batch = db.batch()
        for (index, id) in orderedAssignmentIds.enumerated() {
            batch.updateData(["order": index], forDocument: db.collection("daily_job_assignments").document(id))
        }
        try await batch.commit()

        if let rule = dailyJobRepeatRules[staffId], rule.enabled {
            let orderedTemplateIds = orderedAssignmentIds.compactMap { id in
                dailyJobAssignments.first(where: { $0.id == id })?.templateId
            }
            guard Set(orderedTemplateIds) == Set(rule.templateIds) else { return }
            try? await setDailyJobRepeat(staffId: staffId, templateIds: orderedTemplateIds, enabled: true)
        }
    }

    /// Turn "repeat these jobs daily" on/off for a staff member, in
    /// `templateIds`' order. `templateIds` is saved even when disabling, so
    /// re-enabling later restores the same selection (and order) instead of
    /// starting from an empty picker.
    func setDailyJobRepeat(staffId: String, templateIds: [String], enabled: Bool) async throws {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        try await db.collection("daily_job_repeats").document(staffId).setData([
            "templateIds": templateIds,
            "enabled": enabled,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": uid
        ])
    }

    /// Backfill "repeat daily" onto this staff member's *already-existing*
    /// upcoming shifts the moment the toggle turns on. Without this, the
    /// repeat rule only takes effect for shifts created AFTER the toggle
    /// (via the auto-repeat hook in `saveShift`) — but a manager typically
    /// rosters days/weeks ahead of time, so tomorrow's shift usually already
    /// exists when the toggle is flipped, and would otherwise silently sit
    /// without jobs until it happened to be recreated. Covers drafts too —
    /// jobs are waiting once published, matching the new-shift auto-repeat
    /// hook's own "even to a draft" behavior. Skips any shift that already
    /// has at least one job assigned (a shift the manager deliberately
    /// customized differently is never overwritten), and the shift the
    /// manager is currently editing (already handled by `setDailyJobs`).
    ///
    /// Concurrent, not sequential — same "backgrounding mid-batch must not
    /// strand the rest" reasoning as `bulkApprove` (ManagerTimesheetsView.swift).
    /// Best-effort per shift and never throws, so one transient failure can't
    /// block the primary Save action this rides alongside.
    func backfillDailyJobRepeat(staffId: String, templateIds: [String], excludingShiftId: String) async {
        guard !templateIds.isEmpty else { return }
        let today = RosterCalendar.todayKey()
        let shiftIdsWithAssignments = Set(dailyJobAssignments.map(\.shiftId))
        let candidates = shifts.filter {
            $0.staffId == staffId &&
            $0.id != excludingShiftId &&
            $0.date >= today &&
            ($0.status == .published || $0.status == .draft) &&
            !shiftIdsWithAssignments.contains($0.id)
        }
        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for shift in candidates {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.applyDailyJobs(
                            shiftId: shift.id, staffId: staffId, date: shift.date,
                            templateIds: templateIds, existing: []
                        )
                    } catch {
                        await Self.log.error("backfillDailyJobRepeat failed for shift \(shift.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    /// Staff toggle: complete or undo. Live listeners propagate the change to
    /// the manager dashboard immediately.
    func setDailyJobCompleted(_ assignment: DailyJobAssignment, completed: Bool) async throws {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        try await db.collection("daily_job_assignments").document(assignment.id).updateData([
            "completed": completed,
            "completedAt": completed ? FieldValue.serverTimestamp() : NSNull(),
            "completedBy": completed ? uid : NSNull()
        ])

        // "All assigned jobs completed": checked here rather than via a
        // server-side aggregate, since the client already holds the sibling
        // list in memory. The live Firestore listener that refreshes
        // dailyJobAssignments hasn't necessarily delivered this write back
        // yet, so check siblings EXCLUDING this one (which we know just
        // became complete) rather than re-reading this assignment's stale
        // cached state.
        if completed {
            let siblings = dailyJobs(forShift: assignment.shiftId).filter { $0.id != assignment.id }
            if !siblings.isEmpty, siblings.allSatisfy({ $0.completed }) {
                Task { await WorkerAPIClient.shared.sendNotification(event: "jobs-all-completed") }
            }
        }
    }

    /// Sorted by the manager's drag-arranged `order` (legacy assignments with
    /// no `order` sort after, alphabetically). Completing a job must NOT
    /// reorder the list (rows jumping under a tapped button reads as the tap
    /// having failed and invites accidental taps on the next row) — `order`
    /// only changes via an explicit reorder, never on completion toggle.
    private func sortedByOrder(_ list: [DailyJobAssignment]) -> [DailyJobAssignment] {
        list.sorted { lhs, rhs in
            switch (lhs.order, rhs.order) {
            case let (l?, r?) where l != r: return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    /// Assignments for a shift, in manager-arranged order.
    func dailyJobs(forShift shiftId: String) -> [DailyJobAssignment] {
        sortedByOrder(dailyJobAssignments.filter { $0.shiftId == shiftId })
    }

    /// Today's shifts, sorted by rostered start — shared by the manager
    /// Dashboard and the Daily Jobs overview page so their definition of
    /// "today" can't drift apart from each other.
    func todaysShifts(now: Date = Date()) -> [Shift] {
        let todayKey = RosterCalendar.todayKey(now)
        return shifts
            .filter { $0.date == todayKey }
            .sorted { $0.rosteredStart < $1.rosteredStart }
    }

    /// Staff bell feed: assignments for today (Adelaide calendar day), in
    /// manager-arranged order — see dailyJobs(forShift:).
    var activeDailyJobsForStaff: [DailyJobAssignment] {
        sortedByOrder(dailyJobAssignments.filter { $0.isVisibleToStaff() })
    }

    /// Incomplete visible jobs — feeds the bell badge alongside unread messages.
    var pendingDailyJobCount: Int {
        activeDailyJobsForStaff.filter { !$0.completed }.count
    }

    // MARK: - Manager task management

    /// Create or update a task. A non-nil `referencePhoto` is compressed and
    /// uploaded; pass nil to keep the existing reference photo on edit.
    func saveTask(
        id: String?,
        title: String,
        description: String?,
        frequency: String,
        date: String?,
        dayOfWeek: [Int]?,
        assignedTo: [String]?,
        dueTime: String?,
        priority: String,
        requiresPhoto: Bool,
        endDate: String?,
        referencePhoto: UIImage? = nil
    ) async throws {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        let docRef = id.map { db.collection("tasks").document($0) } ?? db.collection("tasks").document()
        let previousTask = id.flatMap { tid in tasks.first(where: { $0.id == tid }) }

        var fields: [String: Any] = [
            "title": title,
            "description": description ?? NSNull(),
            "frequency": frequency,
            "date": (frequency == "once" ? date : nil) ?? NSNull(),
            "dayOfWeek": (frequency == "weekly" ? dayOfWeek : nil) ?? NSNull(),
            "assignedTo": (assignedTo?.isEmpty == false ? assignedTo : nil) ?? NSNull(),
            "dueTime": dueTime ?? NSNull(),
            "priority": priority,
            "requiresPhoto": requiresPhoto,
            "endDate": endDate ?? NSNull(),
            // Preserve the existing pause state on edit — only default to
            // active on create. Editing a task must never silently undo a
            // manager's pause (setTaskActive is the sole intentional writer).
            "active": previousTask?.active ?? true
        ]
        if id == nil {
            fields["createdAt"] = FieldValue.serverTimestamp()
            fields["createdBy"] = uid
        } else {
            fields["updatedAt"] = FieldValue.serverTimestamp()
            fields["updatedBy"] = uid
        }

        if let referencePhoto {
            guard let data = ImageCompressor.jpegData(from: referencePhoto) else {
                throw NSError(domain: "RosterRepository", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
            }
            let storageRef = Storage.storage().reference().child("task_ref_photos/\(docRef.documentID)_\(UUID().uuidString).jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await storageRef.putDataAsync(data, metadata: metadata)
            fields["managerPhotoUrl"] = try await storageRef.downloadURL().absoluteString
        }

        let previousAssignedTo = previousTask?.assignedTo
        let isCreate = id == nil
        let shouldNotify = isCreate || RosterTask.assigneesChanged(from: previousAssignedTo, to: assignedTo)

        try await docRef.setData(fields, merge: true)

        // Staff Tasks tab shows the task via the live listener; this push is
        // what surfaces "New task" on the lock screen. Reuses the Worker's
        // existing `message-task` event (manager-only, recipientIds list).
        if shouldNotify {
            let activeStaffIds = allUsers
                .filter { $0.role == .staff && $0.status == .active }
                .map(\.id)
            let recipientIds = RosterTask.notificationRecipientIds(
                assignedTo: assignedTo,
                allActiveStaffIds: activeStaffIds
            )
            if !recipientIds.isEmpty {
                Task {
                    await WorkerAPIClient.shared.sendNotification(
                        event: "message-task",
                        recipientIds: recipientIds
                    )
                }
            }
        }
    }

    /// Pause/resume a task. The active-only listener drops paused tasks, so
    /// both portals stop showing them immediately.
    func setTaskActive(id: String, active: Bool) async throws {
        try await db.collection("tasks").document(id).updateData(["active": active])
    }

    /// Delete a task definition. Completion history is retained.
    func deleteTask(id: String, managerPhotoUrl: String?) async throws {
        if let managerPhotoUrl, !managerPhotoUrl.isEmpty,
           let ref = storageReference(for: managerPhotoUrl) {
            await bestEffort("deleteTaskPhoto") { try await ref.delete() }
        }
        try await db.collection("tasks").document(id).delete()
    }

    /// Manager rejects a completion: the task reopens for that day on the
    /// staff side, and the rejected photo is removed from the cloud (the
    /// manager's local cache keeps a copy of what was rejected).
    func requestTaskRedo(completion: TaskCompletion, reason: String) async throws {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        await deleteCloudObjects(completion.photoUrls)
        try await db.collection("task_completions").document(completion.id).updateData([
            "completed": false,
            "status": "redo",
            "redoReason": reason,
            "reviewedBy": uid,
            "reviewedAt": FieldValue.serverTimestamp(),
            "staffPhotoUrl": NSNull(),
            "staffPhotoUrls": NSNull()
        ])
    }

    /// Manager finished reviewing: remove the photo from Firebase Storage to
    /// stay inside the free tier. The local sandbox copy remains the review
    /// history.
    func deleteTaskCloudPhoto(completion: TaskCompletion) async throws {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        await deleteCloudObjects(completion.photoUrls)
        try await db.collection("task_completions").document(completion.id).updateData([
            "staffPhotoUrl": NSNull(),
            "staffPhotoUrls": NSNull(),
            "reviewedBy": uid,
            "reviewedAt": FieldValue.serverTimestamp()
        ])
    }

    private func deleteCloudObjects(_ urls: [String]) async {
        for url in urls where !url.isEmpty {
            if let ref = storageReference(for: url) {
                await bestEffort("deleteCloudObject") { try await ref.delete() }
            }
        }
    }

    /// 14-day backstop: any photo the manager downloaded over two weeks ago
    /// that is still in Firebase Storage gets deleted. Runs shortly after a
    /// manager signs in; the explicit delete-after-review action handles the
    /// common case.
    func cleanupExpiredTaskCloudPhotos(now: Date = Date()) async {
        guard currentUser?.role == .manager else { return }
        let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
        let expired = taskCompletions.filter { comp in
            guard let downloadedAt = comp.managerDownloadedAt, !comp.photoUrls.isEmpty else { return false }
            return downloadedAt < cutoff
        }
        for comp in expired {
            await deleteCloudObjects(comp.photoUrls)
            await bestEffort("clearExpiredPhotoUrls") {
                try await db.collection("task_completions").document(comp.id)
                    .updateData(["staffPhotoUrl": NSNull(), "staffPhotoUrls": NSNull()])
            }
        }
    }

    /// Save a manager-defined work location (arrayUnion — idempotent for
    /// identical entries). Managers only; the settings write rule enforces it.
    func addLocation(_ location: RosterLocation) async throws {
        try await db.collection("settings").document("locations")
            .setData(["items": FieldValue.arrayUnion([location.asDictionary])], merge: true)
    }

    /// Replace the full saved-locations list (edit/delete from the Account
    /// tab's Locations manager). Existing shifts keep their stored location
    /// string — edits only affect future selections.
    func setLocations(_ locations: [RosterLocation]) async throws {
        try await db.collection("settings").document("locations")
            .setData(["items": locations.map { $0.asDictionary }])
    }

    /// Save company/business details onto settings/app (merged — preserves
    /// any PWA-managed keys on the same document).
    func saveCompanyDetails(_ settings: AppSettings) async throws {
        try await db.collection("settings").document("app")
            .setData(settings.asDictionary, merge: true)
    }

    // MARK: - Wages module (manager-only collection)

    /// Create/update a wage award. Pass nil id to create.
    func saveWageAward(_ award: WageAward) async throws {
        let ref = award.id.isEmpty
            ? db.collection("wages").document()
            : db.collection("wages").document(award.id)
        try await ref.setData(award.asDictionary)
    }

    /// Create/update an earnings line. Pass empty id to create.
    func saveEarningsLine(_ line: EarningsLine) async throws {
        let ref = line.id.isEmpty
            ? db.collection("wages").document()
            : db.collection("wages").document(line.id)
        try await ref.setData(line.asDictionary)
    }

    /// Save a classification earnings line and optionally remove the matching
    /// legacy level embedded on a wage award doc.
    func saveClassificationLine(
        _ line: EarningsLine,
        migrateFromAwardId: String? = nil,
        removeLegacyLevel: String? = nil
    ) async throws {
        try await saveEarningsLine(line)
        guard let awardId = migrateFromAwardId,
              let removeLevel = removeLegacyLevel,
              var award = wageAwards.first(where: { $0.id == awardId }) else { return }
        let before = award.classifications.count
        award.classifications.removeAll { $0.level == removeLevel }
        guard award.classifications.count != before else { return }
        try await saveWageAward(award)
    }

    /// Save a staff member's wage assignment (award/classification/lines).
    func saveStaffWageProfile(_ profile: StaffWageProfile) async throws {
        try await db.collection("wages").document(profile.id).setData(profile.asDictionary)
    }

    /// Delete a classification level embedded on a wage award document.
    func deleteLegacyClassification(awardId: String, level: String) async throws {
        guard var award = wageAwards.first(where: { $0.id == awardId }) else { return }
        let before = award.classifications.count
        award.classifications.removeAll { $0.level == level }
        guard award.classifications.count != before else { return }
        try await saveWageAward(award)
    }

    /// Delete any wages-collection document (award or earnings line).
    func deleteWageDocument(id: String) async throws {
        // If this is an earnings line, drop it from every staff profile that
        // references it first — otherwise a profile's earningsLineIds keeps
        // a dangling id. Rate resolution already degrades gracefully (falls
        // through to the next precedence tier), but it's a data-hygiene gap
        // a manager auditing a staff profile could be confused by: a line
        // "assigned" there that no longer exists in the Wages tab.
        if earningsLines.contains(where: { $0.id == id }) {
            let affectedProfiles = staffWageProfiles.filter { $0.earningsLineIds.contains(id) }
            if !affectedProfiles.isEmpty {
                let batch = db.batch()
                for profile in affectedProfiles {
                    batch.updateData(
                        ["earningsLineIds": profile.earningsLineIds.filter { $0 != id }],
                        forDocument: db.collection("wages").document(profile.id)
                    )
                }
                try await batch.commit()
            }
        }
        try await db.collection("wages").document(id).delete()
    }

    func staffWageProfile(for staffId: String) -> StaffWageProfile? {
        staffWageProfiles.first { $0.staffId == staffId }
    }

    /// The dollar-per-hour rate to display/cost a staff member's hours at,
    /// live (not at payroll-generation time) — wage-profile classification
    /// first, then the bare `hourlyRate` on their user doc. No further
    /// assumption beyond that: a staff member with neither costs $0, not a
    /// guessed number (this used to fall back to a hardcoded $25 — removed
    /// deliberately, see `BusinessRules`'s "Pay defaults" note). Used by
    /// Roster's live cost chip, Reports, and Timesheet detail so they finally
    /// agree with the payslip engine instead of each silently guessing.
    func liveHourlyRate(forStaffId staffId: String, shiftDateKey: String? = nil) -> Double {
        let profile = staffWageProfile(for: staffId)
        let award = profile?.awardId.flatMap { id in wageAwards.first { $0.id == id } }
        if let resolved = StaffWageProfile.loadedRate(profile: profile, award: award, earningsLines: earningsLines, shiftDateKey: shiftDateKey) {
            return resolved
        }
        return user(id: staffId)?.hourlyRate ?? 0
    }

    // MARK: - Payroll (payslips collection; manager-controlled)
    //
    // The ONLY automated step is draft creation. Approve → Submit is always a
    // manual manager action; staff visibility flips exclusively on `submitted`
    // (enforced by the payslips Firestore rules).

    /// Idempotently generate draft payslips for the most recently COMPLETED
    /// week (runs when payroll data arrives; safe to call repeatedly). This is
    /// the client-side stand-in for a server cron: whichever manager session
    /// opens first on/after Monday creates the drafts.
    private func autoGeneratePayrollDraftsIfNeeded() {
        guard currentRole == .manager, !payrollAutoGenAttempted else { return }
        // Wait until the collaborating listeners have delivered.
        guard !allUsers.isEmpty, !timesheets.isEmpty else { return }
        payrollAutoGenAttempted = true
        let lastWeekStart = RosterCalendar.addWeeks(-1, to: RosterCalendar.weekStart())
        Task { [weak self] in
            await self?.bestEffort("payroll auto-generation") {
                _ = try await self?.generateDraftPayslips(weekStart: lastWeekStart)
            }
        }
    }

    /// See `BusinessRules.payrollGaps` — this just supplies live repository data.
    func payrollGaps(weekStart: Date) -> [PayrollGapItem] {
        BusinessRules.payrollGaps(
            shifts: shifts,
            timesheetFor: { [weak self] shiftId in self?.timesheet(forShift: shiftId) },
            nameFor: { [weak self] staffId in self?.user(id: staffId)?.fullName ?? "Unknown staff" },
            weekStart: weekStart
        )
    }

    /// Create draft payslips for every eligible staff member for the week
    /// starting `weekStart` (Adelaide Monday). Eligible = active staff user
    /// with approved timesheet hours in the period and an active (or absent)
    /// wage profile. Existing payslips for the period are never touched —
    /// returns the number of NEW drafts created.
    @discardableResult
    func generateDraftPayslips(weekStart: Date) async throws -> Int {
        guard let manager = currentUser else { return 0 }
        let periodStart = RosterCalendar.dayFormatter.string(from: RosterCalendar.weekStart(weekStart))
        let periodEnd = RosterCalendar.dayFormatter.string(from: RosterCalendar.addDays(6, to: RosterCalendar.weekStart(weekStart)))

        // Fresh from the server, not the live shifts/timesheets cache — see
        // fetchApprovedWorkedHours.
        let hoursByStaff = try await fetchApprovedWorkedHours(periodStart: periodStart, periodEnd: periodEnd)

        var created = 0
        for user in allUsers where user.role == .staff && user.status == .active {
            guard let byDate = hoursByStaff[user.id], !byDate.isEmpty else { continue }
            let profile = staffWageProfile(for: user.id)
            if let profile, !profile.active { continue }
            let docId = Payslip.docId(periodStart: periodStart, staffId: user.id)
            guard payslips.first(where: { $0.id == docId }) == nil else { continue }
            // Double-check the server (local cache may lag on cold start —
            // creating over an edited draft would destroy manager edits).
            let existing = try? await db.collection("payslips").document(docId).getDocument()
            if existing?.exists == true { continue }

            let slip = buildDraftPayslip(docId: docId, user: user, profile: profile,
                                         periodStart: periodStart, periodEnd: periodEnd,
                                         workedHoursByDate: byDate, generatedBy: manager)
            try await db.collection("payslips").document(docId).setData(slip.asDictionary)
            created += 1
        }
        if created > 0 {
            await writePayrollAuditLog(action: "payroll-drafts-generated",
                                       detail: "\(created) draft payslip(s) for week \(periodStart)")
        }
        return created
    }

    /// Approved worked hours per staff per date within `periodStart...periodEnd`,
    /// fetched fresh from the server rather than the live, listener-fed
    /// `shifts`/`timesheets` caches.
    ///
    /// Payroll generation is money-critical and is often the very next
    /// action after a destructive one (e.g. a manager deletes a shift, then
    /// regenerates payslips for that week) — trusting the in-memory cache
    /// here risks recreating pay for hours that were just removed, if the
    /// listener hasn't caught up yet. Root cause of the 2026-08-01 bug:
    /// deleting a staff member's only shift for a week, then regenerating,
    /// recreated their payslip with the deleted shift's hours intact.
    /// `.server` (not the default cache-fallback source) so a connectivity
    /// problem fails loudly instead of silently generating from stale data.
    private func fetchApprovedWorkedHours(periodStart: String, periodEnd: String) async throws -> [String: [String: Double]] {
        let shiftsSnap = try await db.collection("shifts")
            .whereField("date", isGreaterThanOrEqualTo: periodStart)
            .whereField("date", isLessThanOrEqualTo: periodEnd)
            .getDocuments(source: .server)
        let periodShiftsById = Dictionary(
            shiftsSnap.documents.compactMap { Shift(id: $0.documentID, data: $0.data()) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        guard !periodShiftsById.isEmpty else { return [:] }

        let timesheetsSnap = try await db.collection("timesheets")
            .whereField("submittedAt", isGreaterThanOrEqualTo: BusinessRules.managerTimesheetCutoff())
            .getDocuments(source: .server)
        let periodTimesheets = timesheetsSnap.documents.compactMap { Timesheet(id: $0.documentID, data: $0.data()) }

        var hoursByStaff: [String: [String: Double]] = [:]
        for ts in periodTimesheets where ts.status == .approved && ts.workedHours > 0 {
            guard let shift = periodShiftsById[ts.shiftId] else { continue }
            hoursByStaff[ts.staffId, default: [:]][shift.date, default: 0] += ts.workedHours
        }
        return hoursByStaff
    }

    /// Assemble a draft payslip snapshot from the wage profile + approved hours.
    private func buildDraftPayslip(docId: String, user: AppUser, profile: StaffWageProfile?,
                                   periodStart: String, periodEnd: String,
                                   workedHoursByDate: [String: Double],
                                   generatedBy manager: AppUser) -> Payslip {
        let award = profile?.awardId.flatMap { id in wageAwards.first { $0.id == id } }
        // Classification levels live on earnings lines; award.classifications is legacy.
        let resolvedRate = profile?.resolvedHourlyRate(award: award, earningsLines: earningsLines)
        let baseRate = resolvedRate ?? user.hourlyRate ?? 0
        // Trace the resolution — a $0 payslip must be diagnosable from logs.
        if let profile {
            Self.log.info("payroll: \(user.fullName, privacy: .public) rate=\(baseRate) via \(resolvedRate != nil ? "wage profile" : (user.hourlyRate != nil ? "users.hourlyRate" : "NONE"), privacy: .public) (award=\(award?.name ?? "none", privacy: .public), classification=\(profile.classificationLevel ?? "none", privacy: .public), override=\(profile.hourlyRateOverride ?? 0), lines=\(profile.earningsLineIds.count))")
        } else {
            Self.log.warning("payroll: \(user.fullName, privacy: .public) has NO wage profile — rate=\(baseRate) from users.hourlyRate fallback")
        }
        let buckets = PayrollCalculator.hoursBuckets(workedHoursByDate: workedHoursByDate)
        // Position = the role most frequently worked in the period (shift
        // "department" carries the role label, e.g. "Console Operator").
        let roles = shifts.filter {
            $0.staffId == user.id && $0.date >= periodStart && $0.date <= periodEnd
        }.compactMap(\.department)
        let position = Dictionary(grouping: roles, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? ""

        // Fixed-amount earnings lines auto-populate; multiplier/per-unit lines
        // are added at zero quantity for the manager to fill in during review.
        var extras: [PayslipEarning] = []
        for lineId in profile?.earningsLineIds ?? [] {
            guard let line = earningsLines.first(where: { $0.id == lineId }), line.active,
                  line.category != .ordinaryHours, line.category != .overtime else { continue }
            switch line.rateType {
            case .fixedAmount:
                extras.append(PayslipEarning(name: line.displayName, amount: line.fixedRate,
                                             exemptFromTax: line.exemptFromTax,
                                             exemptFromSuper: line.exemptFromSuper))
            case .ratePerUnit, .multipleOfOrdinary:
                let rate = line.rateType == .ratePerUnit ? line.fixedRate : baseRate * line.multiplier
                extras.append(PayslipEarning(name: line.displayName, quantity: 0, rate: rate,
                                             exemptFromTax: line.exemptFromTax,
                                             exemptFromSuper: line.exemptFromSuper))
            }
        }

        // Resolve overtime rate from an assigned overtime-category earnings
        // line's multiplier when the manager configured one (e.g. an
        // "Overtime 2x" double-time line), otherwise fall back to the 1.5x
        // default. Previously this was always the flat default even after
        // assigning such a line to the staff profile — the assignment had
        // no effect on generation.
        let overtimeLine = (profile?.earningsLineIds ?? []).compactMap { lineId in
            earningsLines.first(where: { $0.id == lineId && $0.category == .overtime && $0.active })
        }.first
        let overtimeRate: Double = {
            guard let overtimeLine else { return PayrollCalculator.round2(baseRate * 1.5) }
            switch overtimeLine.rateType {
            case .multipleOfOrdinary:
                return PayrollCalculator.round2(baseRate * overtimeLine.multiplier)
            case .ratePerUnit, .fixedAmount:
                return overtimeLine.fixedRate > 0 ? overtimeLine.fixedRate : PayrollCalculator.round2(baseRate * 1.5)
            }
        }()

        var slip = Payslip(
            id: docId,
            staffId: user.id,
            staffName: user.fullName,
            employeeId: user.employeeId ?? "",
            tfnLast4: TFN.last4(user.tfn),
            position: position,
            employmentType: profile?.employmentType ?? user.employmentType?.rawValue ?? "",
            awardName: award?.name ?? "",
            awardCode: award?.code ?? "",
            classification: profile?.resolvedClassificationTitle(award: award, earningsLines: earningsLines) ?? "",
            periodStart: periodStart,
            periodEnd: periodEnd,
            baseHourlyRate: baseRate,
            ordinaryHours: PayrollCalculator.round2(buckets.ordinary),
            weekendHours: PayrollCalculator.round2(buckets.weekend),
            // Weekend & PH: explicit classification rate wins; otherwise defaults.
            weekendRate: {
                let explicit = profile?.resolvedWeekendRate(award: award, earningsLines: earningsLines)
                return (explicit ?? 0) > 0
                    ? explicit!
                    : PayrollCalculator.round2(baseRate * 1.5)
            }(),
            // There is no dedicated public-holiday-rate field on
            // AwardClassification/EarningsLine yet (only weekendHourlyRate),
            // so — unlike weekendRate just above — this always uses the
            // 2.25x default multiplier rather than resolvedWeekendRate.
            // Reusing that weekend resolver here was a bug: the moment a
            // classification had an explicit weekend override, PH hours
            // would silently price at the (lower) weekend rate instead of
            // the correct PH loading. A manager can still override the
            // generated value per-payslip in the Hours section before
            // publishing. TODO: add a real publicHolidayHourlyRate field +
            // resolver once the Wages module supports one.
            publicHolidayRate: PayrollCalculator.round2(baseRate * 2.25),
            overtimeRate: overtimeRate,
            extraEarnings: extras,
            claimsTaxFreeThreshold: profile?.claimsTaxFreeThreshold ?? true,
            // Profile controls super: OFF (e.g. under-18) ⇒ 0%, payslip and
            // PDF then omit the super block entirely.
            superRate: profile?.resolvedSuperRate(userDefault: user.superRate) ?? (user.superRate ?? BusinessRules.defaultSuperRatePercent),
            generatedAt: Date(),
            audit: [PayslipAuditEntry(action: "generated", userId: manager.id,
                                      userName: manager.fullName,
                                      detail: baseRate > 0
                                        ? "Auto-generated from approved timesheets"
                                        : "Auto-generated — no wage rate resolved: assign an award classification, a rate override, or an ordinary-hours line with a $ rate, then Regenerate")]
        )
        // ATO Schedule 1 (NAT 1004) weekly formula — see PAYGCalculator. Still
        // manager-editable afterwards for declarations the formula doesn't
        // model (HELP/STSL debt, foreign residency, etc).
        slip.payg = PayrollCalculator.calculatedPAYG(for: slip)
        return slip
    }

    /// Persist manager edits to a payslip (draft/under-review only — callers
    /// guard on `status.isEditable`; submitted payroll is immutable).
    /// `original` is the pre-edit snapshot this editing session started
    /// from — used to log one field-level audit entry per changed value
    /// (see `PayrollCalculator.auditDiff`) instead of one generic "edited"
    /// blob. No entry is appended if nothing actually changed.
    func savePayslip(_ slip: Payslip, original: Payslip, editedBy editor: AppUser) async throws {
        var updated = slip
        updated.updatedAt = Date()
        updated.audit.append(contentsOf: PayrollCalculator.auditDiff(from: original, to: slip, editor: editor))
        try await db.collection("payslips").document(slip.id).setData(updated.asDictionary)
    }

    /// Move a payslip through the manual workflow. Submitting stamps
    /// `submittedBy/At` — the moment staff visibility flips on.
    func setPayslipStatus(_ slip: Payslip, to status: PayslipStatus, by actor: AppUser) async throws {
        var updated = slip
        updated.status = status
        updated.updatedAt = Date()
        switch status {
        case .approved:
            updated.approvedBy = actor.id
            updated.approvedAt = Date()
        case .submitted:
            updated.submittedBy = actor.id
            updated.submittedAt = Date()
        default: break
        }
        updated.audit.append(PayslipAuditEntry(action: status.rawValue, userId: actor.id,
                                               userName: actor.fullName))
        try await db.collection("payslips").document(slip.id).setData(updated.asDictionary)
        await writePayrollAuditLog(action: "payslip-\(status.rawValue)",
                                   detail: "\(slip.staffName) · week \(slip.periodStart)")
        if status == .submitted {
            // The moment staff visibility flips on — see the doc comment above.
            let staffId = slip.staffId
            Task { await WorkerAPIClient.shared.sendNotification(event: "payslip-generated", recipientIds: [staffId]) }
        }
    }

    /// Delete a DRAFT payslip (managers only; other statuses are kept for the
    /// record — archive instead).
    func deleteDraftPayslip(_ slip: Payslip) async throws {
        guard slip.status == .draft || slip.status == .underReview else { return }
        try await db.collection("payslips").document(slip.id).delete()
        await writePayrollAuditLog(action: "payslip-draft-deleted",
                                   detail: "\(slip.staffName) · week \(slip.periodStart)")
    }

    /// Bulk-delete DRAFT/UNDER-REVIEW payslips in one atomic batch — e.g. "Delete
    /// all drafts" after a batch generation the manager wants to redo. Silently
    /// skips any approved/submitted/archived payslip passed in: those are
    /// official records, same protection as the single-delete above.
    func deleteDraftPayslips(_ slips: [Payslip]) async throws {
        let deletable = slips.filter { $0.status == .draft || $0.status == .underReview }
        guard !deletable.isEmpty else { return }
        let batch = db.batch()
        for slip in deletable {
            batch.deleteDocument(db.collection("payslips").document(slip.id))
        }
        try await batch.commit()
        await writePayrollAuditLog(action: "payslip-drafts-bulk-deleted",
                                   detail: "\(deletable.count) draft payslip(s) · week \(deletable.first?.periodStart ?? "")")
    }

    /// Publish (submit) one or more payslips in a single batch — the fast
    /// path individual/bulk "Publish" uses, jumping straight from whatever
    /// pre-submit status a payslip is in (draft/underReview/approved) to
    /// submitted. Deliberately bypasses the granular Start Review → Approve
    /// → Submit workflow in `ManagerPayslipDetailSheet`, which stays
    /// available separately for managers who still want that control.
    @discardableResult
    func publishPayslips(_ slips: [Payslip], by actor: AppUser) async throws -> Int {
        // Re-filter against live state right before building the batch — a
        // selection captured when the bulk sheet opened could be stale by
        // the time "Publish Selected" is tapped (e.g. deleted elsewhere).
        // `updateData` throws on a missing doc and the batch is atomic, so
        // one stale id would otherwise fail every other selected payslip too.
        let ids = Set(slips.map(\.id))
        let eligible = payslips.filter { ids.contains($0.id) && $0.status != .submitted && $0.status != .archived }
        guard !eligible.isEmpty else { return 0 }

        let batch = db.batch()
        let now = Date()
        for slip in eligible {
            let entry = PayslipAuditEntry(action: "submitted", userId: actor.id,
                                          userName: actor.fullName, detail: "Published")
            batch.updateData([
                "status": PayslipStatus.submitted.rawValue,
                "submittedBy": actor.id,
                "submittedAt": now,
                "updatedAt": now,
                "audit": FieldValue.arrayUnion([entry.asDictionary]),
            ], forDocument: db.collection("payslips").document(slip.id))
        }
        try await batch.commit()
        await writePayrollAuditLog(action: "payslips-published",
                                   detail: "\(eligible.count) payslip(s) published")
        // The moment staff visibility flips on for each of these — mirrors
        // the single-payslip notification in setPayslipStatus, batched.
        await WorkerAPIClient.shared.sendNotification(event: "payslip-generated",
                                                       recipientIds: eligible.map(\.staffId))
        return eligible.count
    }

    /// Regenerate a draft from current timesheet + wage data, REPLACING the
    /// existing draft's amounts (explicit manager action; keeps the audit trail).
    func regenerateDraftPayslip(_ slip: Payslip) async throws {
        guard slip.status.isEditable, let manager = currentUser,
              let user = usersById[slip.staffId] else { return }
        // Fresh from the server, not the live shifts/timesheets cache — see
        // fetchApprovedWorkedHours.
        let hoursByStaff = try await fetchApprovedWorkedHours(periodStart: slip.periodStart, periodEnd: slip.periodEnd)
        let byDate = hoursByStaff[slip.staffId] ?? [:]
        var fresh = buildDraftPayslip(docId: slip.id, user: user,
                                      profile: staffWageProfile(for: slip.staffId),
                                      periodStart: slip.periodStart, periodEnd: slip.periodEnd,
                                      workedHoursByDate: byDate, generatedBy: manager)
        fresh.audit = slip.audit
        fresh.audit.append(PayslipAuditEntry(action: "regenerated", userId: manager.id,
                                             userName: manager.fullName,
                                             detail: "Recalculated from current timesheets and wage assignment"))
        try await db.collection("payslips").document(slip.id).setData(fresh.asDictionary)
    }

    // MARK: - Staff payslips (month-keyed, cache-first)

    /// Staff-visible payslips for one "yyyy-MM" month, cheapest source first:
    /// 1. session memory, 2. Firestore's on-disk cache (zero reads, works
    /// offline), 3. the server. The server is consulted only for months never
    /// fetched on this device, the current month (once per session — new
    /// payslips land there), or `forceRefresh` (pull-to-refresh).
    func staffPayslips(monthKey: String, forceRefresh: Bool = false) async throws -> [Payslip] {
        guard let uid = activeUID else { return [] }
        let isCurrentMonth = monthKey == RosterCalendar.monthKey()
        let needsServer = forceRefresh
            || (isCurrentMonth && !staffPayslipMonthsRefreshed.contains(monthKey))

        if !needsServer, let cached = staffPayslipMonthCache[monthKey] {
            return cached
        }

        guard let query = staffPayslipMonthQuery(uid: uid, monthKey: monthKey) else { return [] }

        if !needsServer {
            // Firestore disk cache: instant and free. An empty result is only
            // trustworthy if this device has downloaded the month before —
            // otherwise the cache just doesn't have it yet.
            if let snap = try? await query.getDocuments(source: .cache) {
                let slips = parseStaffPayslips(snap)
                if !slips.isEmpty || payslipMonthsDownloaded(uid: uid).contains(monthKey) {
                    staffPayslipMonthCache[monthKey] = slips
                    return slips
                }
            }
        }

        let slips: [Payslip]
        do {
            let snap = try await query.getDocuments(source: .server)
            slips = parseStaffPayslips(snap)
        } catch {
            // Defensive: the documentID range should need no composite index
            // (equalities + __name__ bounds), but if the backend ever rejects
            // it, fall back to the equality-only query — the exact shape the
            // old listener used — and bucket the whole history client-side.
            let snap = try await db.collection("payslips")
                .whereField("staffId", isEqualTo: uid)
                .whereField("status", in: [PayslipStatus.submitted.rawValue, PayslipStatus.archived.rawValue])
                .getDocuments(source: .server)
            let all = parseStaffPayslips(snap)
            let byMonth = Dictionary(grouping: all) { String($0.periodStart.prefix(7)) }
            for (month, monthSlips) in byMonth {
                staffPayslipMonthCache[month] = monthSlips
                staffPayslipMonthsRefreshed.insert(month)
                markPayslipMonthDownloaded(month, uid: uid)
            }
            slips = byMonth[monthKey] ?? []
        }

        staffPayslipMonthCache[monthKey] = slips
        staffPayslipMonthsRefreshed.insert(monthKey)
        markPayslipMonthDownloaded(monthKey, uid: uid)
        return slips
    }

    /// Equalities prove the payslips security rule (staffId == uid AND a
    /// staff-visible status); the documentID bounds ride on doc ids being
    /// "{periodStart}_{staffId}" so a month is a lexicographic id range —
    /// no composite index required (__name__ terminates every index).
    private func staffPayslipMonthQuery(uid: String, monthKey: String) -> Query? {
        guard let bounds = RosterCalendar.monthDayKeyBounds(monthKey) else { return nil }
        return db.collection("payslips")
            .whereField("staffId", isEqualTo: uid)
            .whereField("status", in: [PayslipStatus.submitted.rawValue, PayslipStatus.archived.rawValue])
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: bounds.start)
            .whereField(FieldPath.documentID(), isLessThan: bounds.end)
    }

    private func parseStaffPayslips(_ snap: QuerySnapshot) -> [Payslip] {
        snap.documents
            .compactMap { Payslip(id: $0.documentID, data: $0.data()) }
            .filter { $0.status.isStaffVisible }
            .sorted { $0.periodStart > $1.periodStart }
    }

    /// Months this device has downloaded at least once (per user) — lets an
    /// EMPTY cache result be trusted instead of re-hitting the server.
    private func payslipMonthsDownloaded(uid: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "payslipMonthsDownloaded.\(uid)") ?? [])
    }

    private func markPayslipMonthDownloaded(_ monthKey: String, uid: String) {
        var months = payslipMonthsDownloaded(uid: uid)
        guard !months.contains(monthKey) else { return }
        months.insert(monthKey)
        UserDefaults.standard.set(Array(months).sorted(), forKey: "payslipMonthsDownloaded.\(uid)")
    }

    /// Display employee ID for a payslip: the generation snapshot, else the
    /// staff member's current manager-assigned ID (covers payslips generated
    /// before an ID existed). Empty when none is assigned.
    func displayEmployeeId(for slip: Payslip) -> String {
        if !slip.employeeId.isEmpty { return slip.employeeId }
        if let fromDirectory = user(id: slip.staffId)?.employeeId, !fromDirectory.isEmpty {
            return fromDirectory
        }
        if currentUser?.id == slip.staffId, let own = currentUser?.employeeId, !own.isEmpty {
            return own
        }
        return ""
    }

    /// Issue a corrected copy of a submitted payslip: the original is archived
    /// and an editable draft (id suffix `_c2`, `_c3`, …) takes its place.
    func createCorrectedPayslip(from slip: Payslip) async throws {
        guard let manager = currentUser else { return }
        let base = slip.id.components(separatedBy: "_c").first ?? slip.id
        let existingCorrections = payslips.filter { $0.id.hasPrefix("\(base)_c") }.count
        let newId = "\(base)_c\(existingCorrections + 2)"

        let corrected = Payslip(id: newId, staffId: slip.staffId, staffName: slip.staffName,
                            employeeId: slip.employeeId, tfnLast4: slip.tfnLast4,
                            position: slip.position, employmentType: slip.employmentType,
                            awardName: slip.awardName, awardCode: slip.awardCode,
                            classification: slip.classification,
                            periodStart: slip.periodStart, periodEnd: slip.periodEnd,
                            payDate: slip.payDate, status: .draft,
                            baseHourlyRate: slip.baseHourlyRate,
                            ordinaryHours: slip.ordinaryHours, weekendHours: slip.weekendHours,
                            weekendRate: slip.weekendRate,
                            publicHolidayHours: slip.publicHolidayHours,
                            publicHolidayRate: slip.publicHolidayRate,
                            overtimeHours: slip.overtimeHours, overtimeRate: slip.overtimeRate,
                            extraEarnings: slip.extraEarnings,
                            claimsTaxFreeThreshold: slip.claimsTaxFreeThreshold,
                            payg: slip.payg, otherDeductions: slip.otherDeductions,
                            salarySacrifice: slip.salarySacrifice,
                            deductionNotes: slip.deductionNotes, superRate: slip.superRate,
                            notes: slip.notes, generatedAt: Date(),
                            audit: [PayslipAuditEntry(action: "generated", userId: manager.id,
                                                      userName: manager.fullName,
                                                      detail: "Corrected copy of \(slip.id)")])
        try await db.collection("payslips").document(newId).setData(corrected.asDictionary)

        var archived = slip
        archived.status = .archived
        archived.updatedAt = Date()
        archived.audit.append(PayslipAuditEntry(action: "archived", userId: manager.id,
                                                userName: manager.fullName,
                                                detail: "Superseded by corrected copy \(newId)"))
        try await db.collection("payslips").document(slip.id).setData(archived.asDictionary)
        await writePayrollAuditLog(action: "payslip-corrected",
                                   detail: "\(slip.staffName) · week \(slip.periodStart) → \(newId)")
    }

    /// Record a payslip download/print on the document's own audit trail
    /// (manager sessions only — staff cannot write to payslips by rules).
    func recordPayslipDownload(_ slip: Payslip) async {
        guard currentRole == .manager, let actor = currentUser else { return }
        await bestEffort("payslip download audit") { [self] in
            var updated = slip
            updated.audit.append(PayslipAuditEntry(action: "downloaded", userId: actor.id,
                                                   userName: actor.fullName))
            try await db.collection("payslips").document(slip.id)
                .setData(["audit": updated.audit.map { $0.asDictionary }], merge: true)
        }
    }

    /// Best-effort entry in the global `auditLogs` collection (manager-only
    /// writes by rules — never blocks the payroll action itself).
    private func writePayrollAuditLog(action: String, detail: String) async {
        guard let actor = currentUser, currentRole == .manager else { return }
        await bestEffort("auditLogs \(action)") { [self] in
            try await db.collection("auditLogs").document().setData([
                "action": action,
                "detail": detail,
                "userId": actor.id,
                "userName": actor.fullName,
                "at": Date(),
                "area": "payroll",
            ])
        }
    }

    /// Add or update a shift in Firestore (calculating scheduledHours dynamically).
    func saveShift(
        id: String?,
        staffId: String,
        date: String,
        start: String,
        end: String,
        breakMinutes: Int,
        location: String?,
        department: String?,
        notes: String?,
        status: ShiftStatus
    ) async throws {
        let isUpdate = id != nil && !(id?.isEmpty ?? true)
        let existing = isUpdate ? shiftsById[id!] : nil
        let docRef: DocumentReference
        if let id = id, !id.isEmpty {
            docRef = db.collection("shifts").document(id)
        } else {
            docRef = db.collection("shifts").document()
        }

        let startDateTime = BusinessRules.shiftStartDateTime(date: date, time: start)
        let endDateTime = BusinessRules.shiftEndDateTime(date: date, start: start, end: end)
        let diffSecs = endDateTime.timeIntervalSince(startDateTime)
        let diffHours = diffSecs / 3600.0
        let scheduledHours = max(0.0, diffHours - (Double(breakMinutes) / 60.0))
        // Mirrors the PWA's dataStore.ts updateShift: true when either the
        // date or start time actually differs from what's currently saved.
        // Resets the shift-start reminder flags (matching the PWA) and is
        // the same condition that gates the shift-changed notification below.
        let startChanged = existing != nil && (existing!.date != date || existing!.rosteredStart != start)

        var data: [String: Any] = [
            "staffId": staffId,
            "date": date,
            "rosteredStart": start,
            "rosteredEnd": end,
            "breakMinutes": breakMinutes,
            "scheduledHours": scheduledHours,
            "location": location ?? "",
            "department": department ?? "",
            "notes": notes ?? "",
            "status": status.rawValue,
            // REQUIRED by Firestore rules and the Worker crons: staff can only
            // create/update a timesheet when the shift has `submittableAfter`
            // as a timestamp (isSubmittableStaffShift), and the shift-start
            // reminder crons key off `shiftStartAt`. The web app writes and
            // backfills both; the native app must too. Recomputed on every
            // save so date/time edits stay consistent.
            "shiftStartAt": Timestamp(date: startDateTime),
            "submittableAfter": Timestamp(date: endDateTime),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if startChanged {
            data["startReminder6hSent"] = false
            data["startReminder30mSent"] = false
        }

        try await docRef.setData(data, merge: true)

        // New shift for a staff member with "repeat daily jobs" enabled —
        // carry their standing job selection onto this shift so the manager
        // doesn't have to reopen Daily Jobs and re-pick every day. Applied
        // even to a draft (so the jobs are already there once published);
        // best-effort so a failure here never blocks shift creation itself.
        if !isUpdate, let rule = dailyJobRepeatRules[staffId], rule.enabled, !rule.templateIds.isEmpty {
            let shiftId = docRef.documentID
            do {
                let addedAny = try await applyDailyJobs(
                    shiftId: shiftId, staffId: staffId, date: date,
                    templateIds: rule.templateIds, existing: []
                )
                if addedAny, status == .published {
                    Task { await WorkerAPIClient.shared.sendNotification(event: "job-assigned", recipientIds: [staffId]) }
                }
            } catch {
                Self.log.error("applyDailyJobs(repeat) failed for shift \(shiftId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Only notify for a published shift's start-time change — a draft
        // edit is invisible to staff.
        if startChanged, existing?.status == .published {
            let shiftId = docRef.documentID
            Task { await WorkerAPIClient.shared.sendNotification(event: "shift-changed", shiftIds: [shiftId]) }
        }
    }

    /// Delete a shift and any timesheets attached to it (one atomic batch),
    /// so deletions no longer strand orphaned timesheets that inflate the
    /// Dashboard pending count while being invisible in week views.
    /// (Manager timesheet deletes are permitted by the deployed rules.)
    func deleteShift(id: String) async throws {
        // Captured before the delete — staffId can no longer be looked up
        // server-side once the doc is gone, and only notify if the shift was
        // published (staff never saw a draft).
        let existing = shiftsById[id]
        let attached = try await db.collection("timesheets")
            .whereField("shiftId", isEqualTo: id)
            .getDocuments()
        let batch = db.batch()
        batch.deleteDocument(db.collection("shifts").document(id))
        for doc in attached.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()

        if let existing, existing.status == .published {
            let staffId = existing.staffId
            Task { await WorkerAPIClient.shared.sendNotification(event: "shift-cancelled", recipientIds: [staffId]) }
        }
    }

    /// Fields written when a shift is published. Mirrors the PWA's
    /// `publishShifts` (dataStore.ts): status + publishedAt + updatedAt, and
    /// backfills `shiftStartAt`/`submittableAfter` so drafts created before
    /// those fields existed become submittable once published.
    private func publishFields(date: String, start: String, end: String) -> [String: Any] {
        [
            "status": ShiftStatus.published.rawValue,
            "publishedAt": nowISO(),
            "updatedAt": FieldValue.serverTimestamp(),
            "shiftStartAt": Timestamp(date: BusinessRules.shiftStartDateTime(date: date, time: start)),
            "submittableAfter": Timestamp(date: BusinessRules.shiftEndDateTime(date: date, start: start, end: end))
        ]
    }

    /// Publish a single shift (context-menu / swipe action).
    func publishShift(_ shift: Shift) async throws {
        try await db.collection("shifts").document(shift.id).updateData(
            publishFields(date: shift.date, start: shift.rosteredStart, end: shift.rosteredEnd)
        )
        // Same event as the bulk path (publishAllDrafts) — the assigned staff
        // member otherwise never learns their shift went live until they
        // happen to reopen the app.
        await WorkerAPIClient.shared.sendNotification(event: "roster-published", shiftIds: [shift.id])
    }

    /// Publish all draft shifts for a given date range (firstKey to lastKey).
    ///
    /// The date filter is the only server-side clause: combining it with a
    /// `status == draft` filter requires a `(status, date)` composite index
    /// that is NOT in the deployed indexes (only `(staffId, status, date)`
    /// exists), so that query fails on device with FAILED_PRECONDITION —
    /// this was why publishing from the iPad failed while the PWA (which
    /// batch-updates ids it already holds in memory) succeeded. Drafts are
    /// filtered client-side instead.
    func publishAllDrafts(from firstKey: String, to lastKey: String) async throws {
        let snap = try await db.collection("shifts")
            .whereField("date", isGreaterThanOrEqualTo: firstKey)
            .whereField("date", isLessThanOrEqualTo: lastKey)
            .getDocuments()

        let drafts = snap.documents.filter {
            ($0.data()["status"] as? String) == ShiftStatus.draft.rawValue
        }
        guard !drafts.isEmpty else { return }

        // Firestore batches cap at 500 operations — chunk like the PWA does.
        for chunkStart in stride(from: 0, to: drafts.count, by: 500) {
            let batch = db.batch()
            for doc in drafts[chunkStart..<min(chunkStart + 500, drafts.count)] {
                let data = doc.data()
                batch.updateData(
                    publishFields(date: FS.stringValue(data, "date"),
                                  start: FS.stringValue(data, "rosteredStart"),
                                  end: FS.stringValue(data, "rosteredEnd")),
                    forDocument: doc.reference
                )
            }
            try await batch.commit()
        }
        // Notify affected staff their roster is out (event name from the
        // Worker's registry; recipient resolution happens server-side).
        await WorkerAPIClient.shared.sendNotification(event: "roster-published",
                                                      shiftIds: drafts.map { $0.documentID })
    }

    /// Lock or unlock staff availability for a roster week (manager only —
    /// the settings write rule enforces it). Locked weeks are enforced
    /// server-side by the Worker's availability endpoint on both platforms.
    func setAvailabilityWeekLock(weekKey: String, locked: Bool) async throws {
        let ref = db.collection("settings").document("availabilityLocks")
        // Ensure the doc exists — updateData on a missing doc throws NOT_FOUND.
        try await ref.setData([:], merge: true)
        // Dot-path updates merge into the nested `weeks` map. Do NOT use
        // setData(["weeks": [weekKey: true]], merge: true) — on iOS that
        // replaces the entire map and wipes sibling week locks (breaks PWA).
        if locked {
            try await ref.updateData(["weeks.\(weekKey)": true])
            lockedAvailabilityWeeks.insert(weekKey)
        } else {
            try await ref.updateData(["weeks.\(weekKey)": FieldValue.delete()])
            lockedAvailabilityWeeks.remove(weekKey)
        }
    }

    /// Approve a pending timesheet — sets status = .approved, managerNotes, approvedBy, and approvedAt.
    /// Manager correction of a submitted timesheet's times (typo fixes, staff
    /// forgot to end shift, …). The rostered times on the shift are untouched
    /// — they stay the primary reference — and the attendance record keeps
    /// the original verified clock-in/out for audit.
    func managerAdjustTimesheet(id: String, actualStart: String, actualEnd: String,
                                breakMinutes: Int) async throws {
        let worked = BusinessRules.calcWorkedHours(start: actualStart, end: actualEnd,
                                                   breakMinutes: breakMinutes)
        try await db.collection("timesheets").document(id).updateData([
            "actualStart": actualStart,
            "actualEnd": actualEnd,
            "actualBreakMinutes": breakMinutes,
            "workedHours": worked,
            "adjustedByManagerAt": nowISO(),
            "updatedAt": nowISO(),
        ])
    }

    /// Runs `updateData` inside a transaction that first reads the
    /// timesheet's current status and aborts if it isn't one of
    /// `actionableStatuses` — without this, two managers (or the detail
    /// sheet racing the grid's context menu / a bulk-approve) acting on the
    /// same doc could silently overwrite each other's decision with no
    /// conflict surfaced to either party.
    private func updateTimesheetIfActionable(
        id: String, actionableStatuses: Set<TimesheetStatus>, data: [String: Any]
    ) async throws {
        let docRef = db.collection("timesheets").document(id)
        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(docRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            let currentStatus = (snapshot.data()?["status"] as? String).flatMap(TimesheetStatus.init(rawValue:))
            guard let currentStatus, actionableStatuses.contains(currentStatus) else {
                errorPointer?.pointee = NSError(
                    domain: "RosterRepository", code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "This timesheet was already handled — refresh and try again."]
                )
                return nil
            }
            transaction.updateData(data, forDocument: docRef)
            return nil
        }
    }

    func approveTimesheet(id: String, managerNotes: String?) async throws {
        guard let currentUserId = currentUser?.id else { return }
        try await updateTimesheetIfActionable(
            id: id,
            actionableStatuses: [.pending],
            data: timesheetApprovalData(managerNotes: managerNotes, approvedBy: currentUserId)
        )
        notifyTimesheetsApproved([id])
    }

    /// Approve many pending timesheets in one Firestore batch instead of
    /// waiting on a transaction + worker notification per row. Notifications
    /// go out after the write, without blocking the manager.
    func approveTimesheets(ids: [String], managerNotes: String? = nil) async -> (approvedIds: [String], failedIds: [String]) {
        let uniqueIds = Array(Set(ids))
        guard let currentUserId = currentUser?.id, !uniqueIds.isEmpty else {
            return ([], uniqueIds)
        }
        let data = timesheetApprovalData(managerNotes: managerNotes, approvedBy: currentUserId)

        do {
            try await commitTimesheetApprovals(ids: uniqueIds, data: data)
            notifyTimesheetsApproved(uniqueIds)
            return (uniqueIds, [])
        } catch {
            var approvedIds: [String] = []
            var failedIds: [String] = []
            await withTaskGroup(of: (String, Bool).self) { group in
                for id in uniqueIds {
                    group.addTask {
                        do {
                            try await self.updateTimesheetIfActionable(
                                id: id, actionableStatuses: [.pending], data: data
                            )
                            return (id, true)
                        } catch {
                            return (id, false)
                        }
                    }
                }
                for await (id, succeeded) in group {
                    if succeeded { approvedIds.append(id) } else { failedIds.append(id) }
                }
            }
            notifyTimesheetsApproved(approvedIds)
            return (approvedIds, failedIds)
        }
    }

    private func timesheetApprovalData(managerNotes: String?, approvedBy: String) -> [String: Any] {
        [
            "status": TimesheetStatus.approved.rawValue,
            "managerNotes": managerNotes ?? "",
            "approvedBy": approvedBy,
            "approvedAt": nowISO(),
            "updatedAt": nowISO()
        ]
    }

    private func commitTimesheetApprovals(ids: [String], data: [String: Any]) async throws {
        let chunkSize = 500
        var index = 0
        while index < ids.count {
            let end = min(index + chunkSize, ids.count)
            let batch = db.batch()
            for id in ids[index..<end] {
                batch.updateData(data, forDocument: db.collection("timesheets").document(id))
            }
            try await batch.commit()
            index = end
        }
    }

    private func notifyTimesheetsApproved(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        Task {
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask {
                        await WorkerAPIClient.shared.sendNotification(
                            event: "timesheet-approved", timesheetId: id
                        )
                    }
                }
            }
        }
    }

    /// Confirm a staff-reported absence — sets status = .absent (terminal).
    /// Mirrors approveTimesheet's audit fields (who/when) but the terminal
    /// state is the manager-confirmed absence rather than an approved timesheet,
    /// so a no-show is never counted as approved worked hours.
    func confirmAbsence(id: String, managerNotes: String?) async throws {
        guard let currentUserId = currentUser?.id else { return }

        let data: [String: Any] = [
            "status": TimesheetStatus.absent.rawValue,
            "managerNotes": managerNotes ?? "",
            "approvedBy": currentUserId,
            "approvedAt": nowISO(),
            "updatedAt": nowISO()
        ]

        try await updateTimesheetIfActionable(id: id, actionableStatuses: [.absentReported], data: data)
    }

    /// Reject a timesheet — sets status = .rejected, managerNotes, and rejectedReason.
    func rejectTimesheet(id: String, reason: String, managerNotes: String?) async throws {
        // rejectedAt/rejectionReminderCount reset here (the only place a
        // timesheet transitions TO .rejected) so the escalating-reminder
        // cron always starts a fresh cycle, matching the PWA's dataStore.ts.
        let data: [String: Any] = [
            "status": TimesheetStatus.rejected.rawValue,
            "rejectedReason": reason,
            "managerNotes": managerNotes ?? "",
            "updatedAt": nowISO(),
            "rejectedAt": FieldValue.serverTimestamp(),
            "rejectionReminderCount": 0
        ]

        // A rejection can apply to either a regular submission or an
        // absence report — both are pre-decision, actionable states.
        try await updateTimesheetIfActionable(id: id, actionableStatuses: [.pending, .absentReported], data: data)
        Task {
            await WorkerAPIClient.shared.sendNotification(event: "timesheet-rejected", timesheetId: id)
        }
    }
}
