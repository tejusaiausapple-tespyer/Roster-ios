#if targetEnvironment(macCatalyst)
import Foundation
import SwiftUI

extension View {
    /// Mac Catalyst's `NavigationSplitView` columns and sheets do not reliably
    /// inherit `@Observable` values from `@Environment(Type.self)`. Re-inject
    /// from a parent that already resolved the objects.
    func macObserved(
        repo: RosterRepository,
        auth: AuthViewModel,
        nav: MacNavigationModel,
        toasts: MacToastCenter
    ) -> some View {
        environment(repo)
            .environment(auth)
            .environment(nav)
            .environment(toasts)
    }

    func macObserved(repo: RosterRepository, toasts: MacToastCenter) -> some View {
        environment(repo).environment(toasts)
    }

    func macObserved(repo: RosterRepository, auth: AuthViewModel) -> some View {
        environment(repo).environment(auth)
    }
}

// MARK: - Type aliases used by the Mac UI

typealias StaffMember = AppUser
typealias DailyJob = DailyJobAssignment
typealias StaffPayslip = Payslip

struct MacCompanyDetails {
    var name: String
    var abn: String
    var address: String
}

struct MacPayslipLineItem: Identifiable {
    let id: String
    let description: String
    let hours: Double
    let rate: Double
    var total: Double { hours * rate }
}

struct MacStaffAvailability {
    let staffId: String
    let days: [Weekday: DayAvailability]

    func isAvailable(onDay raw: String) -> Bool {
        guard let weekday = Weekday(rawValue: raw.lowercased()) else { return true }
        return days[weekday]?.available ?? true
    }

    func notesForDay(_ raw: String) -> String? {
        guard let weekday = Weekday(rawValue: raw.lowercased()) else { return nil }
        let day = days[weekday]
        guard let day, day.available, !day.allDay else { return nil }
        switch (day.start, day.end) {
        case let (start?, end?): return "\(start)–\(end)"
        default: return nil
        }
    }
}

// MARK: - RosterCalendar helpers

extension RosterCalendar {
    static func startOfWeek(for date: Date) -> Date {
        weekStart(date)
    }

    static func todayString() -> String {
        todayKey()
    }

    static func dateString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func todayFormattedLong() -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter.string(from: Date())
    }

    static func formatDateRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    static func dayOfWeek(from date: Date) -> String {
        weekday(for: date).shortLabel
    }

    static func dayOfMonth(from date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }
}

// MARK: - AppUser

extension AppUser {
    var name: String { fullName }
    var roleTitle: String? { defaultDepartment }
    var createdDateFormatted: String? { memberSince }

    var superFundName: String {
        get { "" }
        set { }
    }

    var superMemberNumber: String {
        get { "" }
        set { }
    }
}

// MARK: - Shift

extension Shift {
    var startTime: String {
        get { rosteredStart }
        set { rosteredStart = newValue }
    }

    var endTime: String {
        get { rosteredEnd }
        set { rosteredEnd = newValue }
    }

    var position: String {
        get { department ?? "Staff" }
        set { department = newValue }
    }

    var locationId: String? {
        get { location }
        set { location = newValue }
    }

    var unpaidBreakMinutes: Int {
        get { breakMinutes }
        set { breakMinutes = newValue }
    }

    var durationHours: Double { scheduledHours }

    var durationFormatted: String {
        String(format: "%.1fh", scheduledHours)
    }

    var locationName: String { location ?? "" }

    var actualStartTime: String? { nil }
    var actualEndTime: String? { nil }
    var staffNotes: String? { notes }

    func staffDisplayStatus(timesheet: Timesheet?, at now: Date = Date()) -> StaffShiftDisplayStatus {
        BusinessRules.displayStatus(for: self, timesheet: timesheet, at: now)
    }
}

// MARK: - Payslip

extension Payslip {
    var periodRangeFormatted: String { "\(periodStart) – \(periodEnd)" }
    var netPay: Double { totals.net }
    var grossPay: Double { totals.gross }
    var taxWithheld: Double { totals.tax }

    var items: [MacPayslipLineItem] {
        var rows: [MacPayslipLineItem] = []
        if ordinaryHours > 0 {
            rows.append(MacPayslipLineItem(id: "ordinary", description: "Ordinary hours", hours: ordinaryHours, rate: baseHourlyRate))
        }
        if weekendHours > 0 {
            rows.append(MacPayslipLineItem(id: "weekend", description: "Weekend hours", hours: weekendHours, rate: weekendRate))
        }
        if publicHolidayHours > 0 {
            rows.append(MacPayslipLineItem(id: "ph", description: "Public holiday hours", hours: publicHolidayHours, rate: publicHolidayRate))
        }
        if overtimeHours > 0 {
            rows.append(MacPayslipLineItem(id: "ot", description: "Overtime", hours: overtimeHours, rate: overtimeRate))
        }
        for extra in extraEarnings {
            rows.append(MacPayslipLineItem(id: extra.id, description: extra.name, hours: extra.quantity, rate: extra.rate))
        }
        return rows
    }
}

// MARK: - Daily jobs, tasks, locations, clock, timesheets, messages

extension DailyJobAssignment {
    var assignedStaffId: String { staffId }
    var isCompleted: Bool { completed }
}

extension RosterTask {
    var assignedStaffId: String? { assignedTo?.first }
    var dueDate: String? { date ?? dueTime }
    var locationName: String? { nil }
}

extension RosterLocation {
    var name: String { displayName }
    var address: String { displayName }
    var radiusMeters: Double { effectiveGeofenceRadius }
}

extension ClockSession {
    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = RosterCalendar.timeZone
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeStyle = .short
        return formatter.string(from: clockInAt)
    }

    var elapsedDurationString: String {
        let total = Int(workedSeconds())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}

extension Timesheet {
    var totalHours: Double { workedHours }
    var breakMinutes: Int { actualBreakMinutes }
    var notes: String? { staffNotes }
}

extension Message {
    var title: String { type?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Message" }
    var authorName: String { senderName ?? "Manager" }
    var formattedDate: String { sentAt }
    var content: String { body }
}

extension PayslipPDFService {
    static func generatePDFData(for payslip: Payslip, company: MacCompanyDetails?) -> Data? {
        let settings = AppSettings(
            companyName: company?.name.isEmpty == false ? (company?.name ?? "Rosterra") : "Rosterra",
            businessAddress: company?.address ?? "",
            abn: company?.abn ?? ""
        )
        return render(payslip, settings: settings)
    }
}

extension AuthViewModel {
    func authenticateDevice() async {
        _ = await verifyDeviceAuth()
    }

    func signIn(email: String, password: String) async throws {
        await login(email: email, password: password)
        if let errorMessage {
            throw AuthError.generic(errorMessage)
        }
    }

    func signOut() {
        logout()
    }

    func sendPasswordReset(email: String) async throws {
        try await AuthService.shared.sendPasswordReset(email: email)
    }

    func updatePassword(currentPassword: String, newPassword: String) async throws {
        guard let email = AuthService.shared.currentEmail else { throw AuthError.notAuthenticated }
        try await AuthService.shared.changePassword(current: currentPassword, new: newPassword, email: email)
    }

    func enableDeviceAuth() async {
        guard let uid else { return }
        do {
            try await DeviceAuthService.shared.enable(uid: uid)
            deviceAuthEnabled = true
            deviceAuthVerified = true
        } catch {
            deviceAuthEnabled = false
        }
    }

    func disableDeviceAuth() {
        guard let uid else { return }
        DeviceAuthService.shared.disable(uid: uid)
        deviceAuthEnabled = false
    }
}

// MARK: - Repository surface used by Mac screens

extension RosterRepository {
    var staffMembers: [AppUser] {
        allUsers.filter { $0.role == .staff }
    }

    var dailyJobs: [DailyJobAssignment] { dailyJobAssignments }

    var companyDetails: MacCompanyDetails? {
        MacCompanyDetails(
            name: appSettings.companyName,
            abn: appSettings.abn,
            address: appSettings.businessAddress.isEmpty
                ? AppSettings.composedAddress(
                    street: appSettings.businessStreet,
                    suburb: appSettings.businessSuburb,
                    state: appSettings.businessState
                )
                : appSettings.businessAddress
        )
    }

    var activeClockSession: ClockSession? { clockSession }

    var announcements: [Message] { messages.filter { $0.isActive() } }

    var staffAvailability: [MacStaffAvailability] {
        staffMembers.map { staff in
            let weekKey = RosterCalendar.weekStartKey()
            let weekly = staff.weeklyAvailability[weekKey] ?? staff.availability ?? .defaultAvailability
            return MacStaffAvailability(staffId: staff.id, days: weekly.days)
        }
    }

    func isTaskCompleted(_ task: RosterTask) -> Bool {
        guard let id = task.id else { return false }
        let today = RosterCalendar.todayKey()
        return taskCompletions.contains {
            $0.taskId == id && $0.date == today && $0.completed && $0.status != "redo"
        }
    }

    func timesheetDate(_ timesheet: Timesheet) -> String {
        shiftsById[timesheet.shiftId]?.date ?? timesheet.shiftId
    }

    func createTask(title: String, description: String, assignedStaffId: String?) async throws {
        try await saveTask(
            id: nil,
            title: title,
            description: description.isEmpty ? nil : description,
            frequency: "once",
            date: RosterCalendar.todayKey(),
            dayOfWeek: nil,
            assignedTo: assignedStaffId.map { [$0] },
            dueTime: nil,
            priority: "normal",
            requiresPhoto: false,
            endDate: nil
        )
    }

    func toggleTaskCompletion(taskId: String?, note: String) async throws {
        guard let taskId else { return }
        let today = RosterCalendar.todayKey()
        if taskCompletions.contains(where: {
            $0.taskId == taskId && $0.date == today && $0.completed && $0.status != "redo"
        }) {
            return
        }
        try await completeTask(taskId: taskId, date: today, images: [], note: note.isEmpty ? nil : note)
    }

    func toggleDailyJobCompletion(jobId: String) async throws {
        guard let job = dailyJobAssignments.first(where: { $0.id == jobId }) else { return }
        try await setDailyJobCompleted(job, completed: !job.completed)
    }

    func inviteStaffMember(name: String, email: String, roleTitle: String) async throws {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10)
        let password = "Temp\(token)A1"
        _ = try await createStaff(
            fullName: name,
            email: email,
            password: String(password),
            employmentType: .casual,
            phone: nil,
            startDate: nil,
            defaultDepartment: roleTitle.isEmpty ? nil : roleTitle
        )
    }

    func publishWeekRoster(weekStartDate: String) async throws {
        guard let start = RosterCalendar.dateFromKey(weekStartDate) else { return }
        let days = RosterCalendar.weekDays(for: start)
        let first = dateString(days.first ?? start)
        let last = dateString(days.last ?? start)
        try await publishAllDrafts(from: first, to: last)
    }

    func createShift(
        staffId: String,
        date: String,
        startTime: String,
        endTime: String,
        position: String,
        locationId: String?
    ) async throws {
        try await saveShift(
            id: nil,
            staffId: staffId,
            date: date,
            start: startTime,
            end: endTime,
            breakMinutes: 30,
            location: locationId,
            department: position,
            notes: nil,
            status: .draft
        )
    }

    func updateShift(_ shift: Shift) async throws {
        try await saveShift(
            id: shift.id,
            staffId: shift.staffId,
            date: shift.date,
            start: shift.rosteredStart,
            end: shift.rosteredEnd,
            breakMinutes: shift.breakMinutes,
            location: shift.location,
            department: shift.department,
            notes: shift.notes,
            status: shift.status
        )
    }

    func deleteShift(_ id: String) async throws {
        try await deleteShift(id: id)
    }

    func submitShiftTimesheet(
        shiftId: String,
        actualStartTime: String,
        actualEndTime: String,
        notes: String
    ) async throws {
        guard let uid = currentUser?.id else { throw AuthError.notAuthenticated }
        let shift = shiftsById[shiftId]
        let start = BusinessRules.shiftStartDateTime(date: shift?.date ?? RosterCalendar.todayKey(), time: actualStartTime)
        let end = BusinessRules.shiftEndDateTime(
            date: shift?.date ?? RosterCalendar.todayKey(),
            start: actualStartTime,
            end: actualEndTime
        )
        let breakMinutes = shift?.breakMinutes ?? 30
        let hours = max(0, end.timeIntervalSince(start) / 3600.0 - Double(breakMinutes) / 60.0)
        try await submitTimesheet(
            shiftId: shiftId,
            staffId: uid,
            actualStart: actualStartTime,
            actualEnd: actualEndTime,
            breakMinutes: breakMinutes,
            workedHours: hours,
            notes: notes
        )
    }

    func reportShiftAbsence(shiftId: String, reason: String) async throws {
        guard let uid = currentUser?.id else { throw AuthError.notAuthenticated }
        try await reportAbsence(shiftId: shiftId, staffId: uid, reason: reason)
    }

    func approveShiftTimesheet(shiftId: String) async throws {
        try await approveTimesheet(id: shiftId, managerNotes: nil)
    }

    func approveShiftTimesheets(shiftIds: [String]) async -> (approvedIds: [String], failedIds: [String]) {
        await approveTimesheets(ids: shiftIds)
    }

    func rejectShiftTimesheet(shiftId: String, reason: String) async throws {
        try await rejectTimesheet(id: shiftId, reason: reason, managerNotes: nil)
    }

    func startClockSession(staffId: String) async throws {
        let today = RosterCalendar.todayKey()
        guard let shift = shifts.first(where: {
            $0.staffId == staffId && $0.date == today && $0.status == .published
        }) else {
            throw AuthError.generic("No published shift found for today.")
        }
        try await startShift(shift, fix: nil)
    }

    func endCurrentClockSession() async throws {
        guard let session = clockSession, let shift = shiftsById[session.shiftId] else { return }
        try await endShift(shift, fix: nil)
    }

    func saveStaffAvailability(staffId: String, preferences: [String: (available: Bool, note: String)]) async throws {
        var days: [Weekday: DayAvailability] = UserAvailability.defaultAvailability.days
        for (label, value) in preferences {
            guard let weekday = Weekday(rawValue: label.lowercased()) else { continue }
            days[weekday] = DayAvailability(available: value.available, allDay: true)
        }
        try await saveWeeklyAvailability([RosterCalendar.weekStartKey(): UserAvailability(days: days)])
        _ = staffId
    }

    func updateUser(_ user: AppUser) async throws {
        try await updateStaffFields(staffId: user.id, [
            "phone": user.phone ?? "",
            "emergencyContactName": user.emergencyContactName ?? "",
            "emergencyContactPhone": user.emergencyContactPhone ?? "",
            "tfn": user.tfn ?? "",
            "needsSetup": false,
            "profileUpdateRequired": false,
        ])
    }

    private func dateString(_ date: Date) -> String {
        RosterCalendar.dayFormatter.string(from: date)
    }
}
#endif
