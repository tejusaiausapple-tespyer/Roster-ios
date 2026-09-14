import Foundation

#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Owns the single staff shift Live Activity.
///
/// The activity begins when the app is active during the normal clock-in
/// window, survives app suspension/termination, follows clock and break state,
/// and ends when the shift is no longer active. iOS always retains final say
/// over presentation, including when a person explicitly dismisses it.
@MainActor
enum ShiftLiveActivityManager {
    private static var syncTask: Task<Void, Never>?

    static func sync(
        currentUser: AppUser?,
        shifts: [Shift],
        timesheets: [Timesheet],
        dailyJobs: [DailyJobAssignment],
        clockSession: ClockSession?,
        companyName: String,
        now: Date = Date()
    ) {
        #if !targetEnvironment(macCatalyst)
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            await reconcile(
                currentUser: currentUser,
                shifts: shifts,
                timesheets: timesheets,
                dailyJobs: dailyJobs,
                clockSession: clockSession,
                companyName: companyName,
                now: now
            )
        }
        #endif
    }

    static func activeShift(
        staffID: String,
        shifts: [Shift],
        timesheets: [Timesheet],
        clockSession: ClockSession?,
        now: Date
    ) -> Shift? {
        let filedShiftIDs = Set(timesheets.compactMap { timesheet -> String? in
            switch timesheet.status {
            case .pending, .approved, .absentReported, .absent:
                return timesheet.shiftId
            case .draft, .rejected:
                return nil
            }
        })
        // A completed local clock session remains available until its hours
        // are submitted. Exclude that shift so its Live Activity ends rather
        // than falling back to the ready state and offering Start again.
        let endedShiftID = clockSession?.isActive == false ? clockSession?.shiftId : nil

        let eligible = shifts
            .filter {
                $0.staffId == staffID
                    && $0.status == .published
                    && $0.date == RosterCalendar.todayKey(now)
                    && $0.endDateTime > now
                    && !filedShiftIDs.contains($0.id)
                    && $0.id != endedShiftID
            }
            .sorted { $0.startDateTime < $1.startDateTime }

        if let clockSession, clockSession.isActive,
           let clockedShift = eligible.first(where: { $0.id == clockSession.shiftId }) {
            return clockedShift
        }

        return eligible.first {
            now >= $0.startDateTime.addingTimeInterval(-AppConfig.earlyClockInWindow)
        }
    }

    #if !targetEnvironment(macCatalyst)
    private static func reconcile(
        currentUser: AppUser?,
        shifts: [Shift],
        timesheets: [Timesheet],
        dailyJobs: [DailyJobAssignment],
        clockSession: ClockSession?,
        companyName: String,
        now: Date
    ) async {
        guard !Task.isCancelled else { return }
        guard currentUser?.role == .staff,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let staffID = currentUser?.id,
              let shift = activeShift(
                  staffID: staffID,
                  shifts: shifts,
                  timesheets: timesheets,
                  clockSession: clockSession,
                  now: now
              ) else {
            await endAll()
            return
        }

        let state = contentState(
            for: shift,
            clockSession: clockSession,
            dailyJobs: dailyJobs
        )
        let content = ActivityContent(
            state: state,
            staleDate: shift.endDateTime,
            relevanceScore: 1
        )
        let activities = Activity<ShiftLiveActivityAttributes>.activities

        for activity in activities where activity.attributes.shiftID != shift.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if let activity = activities.first(where: { $0.attributes.shiftID == shift.id }) {
            await activity.update(content)
            return
        }

        let attributes = ShiftLiveActivityAttributes(
            shiftID: shift.id,
            companyName: companyName.isEmpty ? "Rosterra" : companyName,
            location: shift.location ?? "",
            startDate: shift.startDateTime,
            endDate: shift.endDateTime
        )
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    private static func contentState(
        for shift: Shift,
        clockSession: ClockSession?,
        dailyJobs: [DailyJobAssignment]
    ) -> ShiftLiveActivityAttributes.ContentState {
        let shiftJobs = dailyJobs.filter { $0.shiftId == shift.id }
        let completedJobs = shiftJobs.filter(\.completed).count
        guard let session = clockSession, session.shiftId == shift.id, session.isActive else {
            return .init(
                phase: .ready,
                clockInDate: nil,
                completedJobs: completedJobs,
                totalJobs: shiftJobs.count
            )
        }
        return .init(
            phase: session.isOnBreak ? .onBreak : .working,
            clockInDate: session.clockInAt,
            completedJobs: completedJobs,
            totalJobs: shiftJobs.count
        )
    }

    private static func endAll() async {
        for activity in Activity<ShiftLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    #endif
}
