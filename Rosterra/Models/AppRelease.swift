import Foundation

// MARK: - AppRelease

struct AppRelease: Identifiable {
    let version: String
    let build: String
    let releaseDate: Date
    let updateType: UpdateType
    let summary: String
    let features: [String]
    let bugFixes: [String]
    /// Short (7-character) git commit SHA for the release cut.
    let commitHash: String

    var id: String { version }

    /// "1.0.0 (1)" — matches the old inline version string format.
    var versionString: String { "\(version) (\(build))" }

    var formattedReleaseDate: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = RosterCalendar.timeZone
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: releaseDate)
    }

    enum UpdateType {
        case major   // Breaking changes, major redesigns
        case minor   // New features, workflow improvements
        case patch   // Bug fixes, minor UI changes

        var label: String {
            switch self {
            case .major: return "Major"
            case .minor: return "Minor"
            case .patch: return "Patch"
            }
        }
    }
}

// MARK: - ReleaseHistory

/// Static registry of all app releases, newest first.
/// To add a release: prepend a new AppRelease to `all`, bump `MARKETING_VERSION` and
/// `CURRENT_PROJECT_VERSION` in project.yml, and run `xcodegen generate`.
enum ReleaseHistory {

    static let all: [AppRelease] = [
        AppRelease(
            version: "1.0.0",
            build: "2",
            releaseDate: releaseDate(2026, 7, 16),
            updateType: .patch,
            summary: "App Store readiness — opaque icon, account deletion, Tenure & Hours, legal links.",
            features: [
                "Manager Tenure & Hours: service tenure from first approved shift, approved hours, KPIs",
                "Account deletion in-app for staff (request + manager approve); owner account not self-deletable",
                "Account → About links to Privacy Policy, Terms of Service, and Contact Support",
            ],
            bugFixes: [
                "App Store 1024 icon is fully opaque (no alpha channel)",
                "NSPhotoLibraryUsageDescription and NSCalendarsWriteOnlyAccessUsageDescription added",
                "PrivacyInfo.xcprivacy declares collected data types for App Privacy answers",
            ],
            commitHash: "8696eff"
        ),
        AppRelease(
            version: "1.0.0",
            build: "1",
            releaseDate: releaseDate(2026, 7, 10),
            updateType: .major,
            summary: "Initial production release of Rosterra — full staff and manager portal.",
            features: [
                "Staff portal: view roster, submit and resubmit timesheets, report absence",
                "Staff portal: clock in/out with GPS geofence recording and break tracking",
                "Staff portal: weekly availability management with manager-controlled week locks",
                "Staff portal: task completion with photo evidence (up to 4 photos per task)",
                "Staff portal: payslips — monthly history, PDF preview, share and print",
                "Staff portal: daily job completions from manager shift assignments",
                "Manager portal: roster CRUD, drag move/copy (drafts), bulk delete, Publish Week",
                "Manager portal: timesheet review with approve/reject and staff notifications",
                "Manager portal: staff directory with per-field editing and email change requests",
                "Manager portal: availability matrix with week-locking control",
                "Manager portal: weekly reports — labour cost, hours, super, timesheet status",
                "Manager portal: wage awards, classification levels, and earnings lines (Xero AU style)",
                "Manager portal: payroll — weekly draft payslips, approve/submit workflow, AU-standard PDF",
                "Manager portal: task management with photo review, redo requests, and cloud retention",
                "Manager portal: daily job templates library with per-shift assignment tracking",
                "Verified shift attendance with server-timestamped clock-in/out and GPS geofence",
                "Biometric (Face ID) app lock with configurable background re-lock",
                "Manager-assigned Employee ID shown on payslips, staff profile, and PDF",
                "Liquid Glass navigation layer on iOS 26+ (ultraThinMaterial fallback on iOS 17–25)",
            ],
            bugFixes: [
                "Resubmit-after-rejection now presents correctly when Shift History is pushed",
                "Publish Week no longer raises FAILED_PRECONDITION on device (date-only query with client-side draft filter)",
                "Manager Availability tab reflects staff saves in real time without navigating away",
                "Classification dropdown in wage assignment matches the Wage tab level order",
                "Payroll resolves wage from the assigned ordinary-hours earnings line — no more $0 payslips",
                "Wage and Payroll tabs open with no dead space above the first card",
                "Staff search field stays pinned during pull-to-refresh",
            ],
            commitHash: "db26368"
        ),
    ]

    static var current: AppRelease { all[0] }

    private static func releaseDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return RosterCalendar.calendar.date(from: c) ?? Date()
    }
}
