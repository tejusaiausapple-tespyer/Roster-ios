import Foundation
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
    var currentUser: AppUser?
    var shifts: [Shift] = []
    var timesheets: [Timesheet] = []
    var messages: [Message] = []
    var appSettings: AppSettings = .fallback
    var tasks: [RosterTask] = []
    var taskCompletions: [TaskCompletion] = []
    var allUsers: [AppUser] = []
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

    /// Live clock-in session for the signed-in staff member (device-local;
    /// see ClockSession for why this can't be written to Firestore live).
    var clockSession: ClockSession?

    var isLoading = true
    var loadError: String?

    private var listeners: [ListenerRegistration] = []
    private var roleListeners: [ListenerRegistration] = []
    private var activeUID: String?
    private var pendingFirstSnapshot: Set<String> = []
    private var currentRole: UserRole? = nil
    private var roleListenersInitialized = false

    private var db: Firestore { Firestore.firestore() }

    // MARK: - Lifecycle

    func start(uid: String) {
        guard activeUID != uid else { return }
        stop()
        activeUID = uid
        loadClockSession(for: uid)
        isLoading = true
        loadError = nil
        pendingFirstSnapshot = ["users", "tasks", "task_completions"]

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
                }
                self.markArrived("users")
            }
        )

        // tasks (active)
        listeners.append(
            db.collection("tasks")
                .whereField("active", isEqualTo: true)
                .addSnapshotListener { [weak self] snap, error in
                    guard let self else { return }
                    if let error { self.handleError(error, label: "tasks"); return }
                    self.tasks = (snap?.documents ?? []).compactMap { try? $0.data(as: RosterTask.self) }
                    self.markArrived("tasks")
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
                self.lockedAvailabilityWeeks = Set(weeks.compactMap { key, value in
                    (value as? Bool) == true ? key : nil
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

            // 4. Wages module: awards, earnings lines, per-staff assignments —
            //    one collection, discriminated by `kind`. Manager-only by rules.
            roleListeners.append(
                db.collection("wages")
                    .addSnapshotListener { [weak self] snap, error in
                        guard let self else { return }
                        if let error { self.handleError(error, label: "wages"); return }
                        let docs = snap?.documents ?? []
                        self.wageAwards = docs.compactMap { WageAward(id: $0.documentID, data: $0.data()) }
                            .sorted { $0.name < $1.name }
                        self.earningsLines = docs.compactMap { EarningsLine(id: $0.documentID, data: $0.data()) }
                            .sorted { $0.name < $1.name }
                        self.staffWageProfiles = docs.compactMap { StaffWageProfile(id: $0.documentID, data: $0.data()) }
                    }
            )
        } else {
            // STAFF LISTENERS (Restricted to own UID):
            
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
                    }
            )
            
            // 3. Own messages (recipient, last 30 days)
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
        allUsers = []
        wageAwards = []
        earningsLines = []
        staffWageProfiles = []
        roleListenersInitialized = false
        currentRole = nil
        clockSession = nil // persisted copy stays on disk for re-sign-in
        isLoading = true
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
        clockSession = ClockSession(shiftId: shiftId, staffId: uid, clockInAt: Date())
        persistClockSession()
    }

    func startClockBreak() {
        clockSession?.startBreak()
        persistClockSession()
    }

    func endClockBreak() {
        clockSession?.endBreak()
        persistClockSession()
    }

    func endClockSession() {
        clockSession?.clockOut()
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
            // Listeners keep serving cached data; surface nothing on a failed manual refresh.
        }
    }

    // MARK: - Derived lookups

    func timesheet(forShift shiftId: String) -> Timesheet? {
        timesheets.first { $0.shiftId == shiftId || $0.id == shiftId }
    }

    func shift(id: String) -> Shift? {
        shifts.first { $0.id == id }
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

    func markMessageRead(_ id: String) async {
        try? await db.collection("messages").document(id).updateData(["read": true])
    }

    func markMessagesRead(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        let batch = db.batch()
        for id in ids {
            batch.updateData(["read": true], forDocument: db.collection("messages").document(id))
        }
        try? await batch.commit()
    }

    /// Complete a task for a given date, uploading the compressed photo to Firebase Storage and saving a local cache copy.
    func completeTask(taskId: String, date: String, image: UIImage?) async throws {
        guard let uid = activeUID else { throw AuthError.notAuthenticated }
        var photoUrl: String? = nil
        
        if let image {
            // 1. Compress image to JPEG (0.5 quality)
            guard let data = image.jpegData(compressionQuality: 0.5) else {
                throw NSError(domain: "RosterRepository", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
            }
            
            // 2. Upload to Firebase Storage
            let storageRef = Storage.storage().reference().child("task_photos/\(taskId)_\(date)_\(UUID().uuidString).jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            _ = try await storageRef.putDataAsync(data, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()
            photoUrl = downloadURL.absoluteString
            
            // 3. Save to local sandbox cache
            TaskPhotoCache.save(image: image, taskId: taskId, date: date)
        }
        
        // 4. Save completion document to Firestore
        let docId = "\(taskId)_\(date)"
        let completionData: [String: Any] = [
            "id": docId,
            "taskId": taskId,
            "date": date,
            "completed": true,
            "completedAt": FieldValue.serverTimestamp(),
            "completedBy": uid,
            "staffPhotoUrl": photoUrl ?? NSNull()
        ]
        
        try await db.collection("task_completions").document(docId).setData(completionData)
    }

    /// Download and save a verification photo locally.
    func downloadAndCachePhoto(taskId: String, date: String, urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        TaskPhotoCache.save(image: image, taskId: taskId, date: date)
        return image
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

    /// Save a staff member's wage assignment (award/classification/lines).
    func saveStaffWageProfile(_ profile: StaffWageProfile) async throws {
        try await db.collection("wages").document(profile.id).setData(profile.asDictionary)
    }

    /// Delete any wages-collection document (award or earnings line).
    func deleteWageDocument(id: String) async throws {
        try await db.collection("wages").document(id).delete()
    }

    func staffWageProfile(for staffId: String) -> StaffWageProfile? {
        staffWageProfiles.first { $0.staffId == staffId }
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

        let data: [String: Any] = [
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
        
        try await docRef.setData(data, merge: true)
    }

    /// Delete a shift and any timesheets attached to it (one atomic batch),
    /// so deletions no longer strand orphaned timesheets that inflate the
    /// Dashboard pending count while being invisible in week views.
    /// (Manager timesheet deletes are permitted by the deployed rules.)
    func deleteShift(id: String) async throws {
        let attached = try await db.collection("timesheets")
            .whereField("shiftId", isEqualTo: id)
            .getDocuments()
        let batch = db.batch()
        batch.deleteDocument(db.collection("shifts").document(id))
        for doc in attached.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
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
        if locked {
            try await ref.setData(["weeks": [weekKey: true]], merge: true)
        } else {
            // Ensure the doc exists before the field delete (updateData on a
            // missing doc throws NOT_FOUND).
            try await ref.setData([:], merge: true)
            try await ref.updateData(["weeks.\(weekKey)": FieldValue.delete()])
        }
    }

    /// Approve a pending timesheet — sets status = .approved, managerNotes, approvedBy, and approvedAt.
    func approveTimesheet(id: String, managerNotes: String?) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        let data: [String: Any] = [
            "status": TimesheetStatus.approved.rawValue,
            "managerNotes": managerNotes ?? "",
            "approvedBy": currentUserId,
            "approvedAt": nowISO(),
            "updatedAt": nowISO()
        ]

        try await db.collection("timesheets").document(id).updateData(data)
        await WorkerAPIClient.shared.sendNotification(event: "timesheet-approved", timesheetId: id)
    }

    /// Reject a timesheet — sets status = .rejected, managerNotes, and rejectedReason.
    func rejectTimesheet(id: String, reason: String, managerNotes: String?) async throws {
        let data: [String: Any] = [
            "status": TimesheetStatus.rejected.rawValue,
            "rejectedReason": reason,
            "managerNotes": managerNotes ?? "",
            "updatedAt": nowISO()
        ]

        try await db.collection("timesheets").document(id).updateData(data)
        await WorkerAPIClient.shared.sendNotification(event: "timesheet-rejected", timesheetId: id)
    }
}
