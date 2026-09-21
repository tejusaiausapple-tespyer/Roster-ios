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
            version: "2.2.1",
            build: "40",
            releaseDate: releaseDate(2026, 9, 21),
            updateType: .patch,
            summary: "Reliable update notifications across iPhone, iPad and Mac.",
            features: [
                "Update requirements can refresh immediately while the app is open",
                "Mac now presents the same required and optional update screens as iPhone and iPad",
            ],
            bugFixes: [
                "App Store version checks now use the Australian storefront where Rosterra is available",
                "Version checks now run reliably on cold launch as well as foreground and login",
                "The production minimum-version policy is stored alongside the release configuration",
            ],
            commitHash: "pending"
        ),
        AppRelease(
            version: "2.2",
            build: "39",
            releaseDate: releaseDate(2026, 9, 20),
            updateType: .minor,
            summary: "Faster Mac roster planning, stronger timesheet controls and more reliable payroll calculations.",
            features: [
                "Mac Roster now includes an in-place weekly availability preview, improved move and copy controls, and bulk deletion for draft shifts",
                "Mac Team Availability has a redesigned no-scroll weekly matrix with clearer coverage and availability states",
                "Managers can review the complete roster history while staff retain a focused four-week availability window",
                "Managers can edit submitted timesheet hours and add or correct breaks, including after approval",
                "Staff receive an upcoming handover reminder showing who starts the next shift",
                "Mac Account settings now includes version information, Privacy Policy and Terms of Service",
            ],
            bugFixes: [
                "Editing payroll hours now recalculates PAYG withholding and superannuation before saving",
                "Manager-added breaks correctly reduce worked hours",
                "Availability previews no longer clip corners or hide weekly data",
                "Mac sheets, cards and action buttons use more consistent sizing and presentation",
            ],
            commitHash: "pending"
        ),
        AppRelease(
            version: "2.1",
            build: "38",
            releaseDate: releaseDate(2026, 9, 16),
            updateType: .major,
            summary: "A new Rosterra identity and a major upgrade across iPhone, iPad and Mac.",
            features: [
                "A completely new Rosterra app logo and refreshed visual identity across iPhone, iPad and Mac",
                "iOS now checks the public App Store version on launch, foreground and login, with a secure mandatory-update gate for unsupported versions",
                "Mac Payroll can generate, preview, share and print approved pay run PDFs containing period totals, staff earnings, final hours and recorded adjustments",
                "Mac Company Details has been redesigned as a full-width, no-scroll business workspace",
                "The Mac manager workspace includes expanded payroll, staff, reporting, roster and business-management workflows",
            ],
            bugFixes: [
                "Pay run PDFs generate without blocking the app and use the native Mac print workflow",
                "PDF previews use the available workspace and scale documents to a readable width",
                "The Rosterra logo remains visible when the Mac sidebar is collapsed",
                "Version-check failures safely preserve access unless a verified supported-version floor requires an update",
            ],
            commitHash: "pending"
        ),
        AppRelease(
            version: "1.2.2",
            build: "37",
            releaseDate: releaseDate(2026, 9, 15),
            updateType: .patch,
            summary: "New app icon, Liquid Glass header fade on every tab, and the Payslips title pill restored.",
            features: [
                "New app icon",
                "iOS scroll-edge fade now applies to the navigation header and custom week/month bars on every tab",
                "Mac Availability matches the staff-by-day matrix with week navigation, lock, and coverage chips",
            ],
            bugFixes: [
                "Payslips tab now shows the screen title pill",
                "Staff Account no longer leaves a blank gap under the header",
                "Navigation bar minimize-on-scroll uses the current SwiftUI API",
            ],
            commitHash: "cf43314"
        ),
        AppRelease(
            version: "1.2.1",
            build: "36",
            releaseDate: releaseDate(2026, 9, 14),
            updateType: .minor,
            summary: "Improved staff navigation, account presentation and Mac manager workflows.",
            features: [
                "Payslips now has a dedicated centre tab for staff, while Tasks is available directly from the Home dashboard",
                "Staff can add a larger profile picture from the refreshed Account header",
                "Mac managers can review complete staff records and edit details directly in the Staff Directory inspector",
            ],
            bugFixes: [
                "Clarified staff Account information and removed internal reminder diagnostics",
            ],
            commitHash: "pending"
        ),
        AppRelease(
            version: "1.1.2",
            build: "34",
            releaseDate: releaseDate(2026, 8, 13),
            updateType: .patch,
            summary: "A Role field for staff profiles, a Daily Jobs overview page, and several reliability fixes.",
            features: [
                "Staff profiles now have a Role field — set once and it auto-fills on every new shift for that staff member, instead of picking it every time",
                "New \"Daily Jobs\" card on the Manager Dashboard opens a one-tap overview of every staff member's jobs for today",
                "Daily Jobs: numbered ordering shown on both the manager assign sheet and the staff list, and job templates can now be renamed",
            ],
            bugFixes: [
                "\"Repeat daily\" now also backfills jobs onto a staff member's already-scheduled upcoming shifts (including drafts), not just shifts created after the toggle is turned on",
                "\"Repeat daily\" backfill runs concurrently with background-task protection, so backgrounding the app mid-batch no longer strands unprocessed shifts",
                "Android: daily-jobs reminders no longer silently stop arming after midnight for a session that stays signed in",
                "Staff directory and Timesheets staff filter now sort names consistently (locale-aware, case-insensitive) A–Z",
                "Staff Role picker no longer silently overwrites a legacy or custom role value it doesn't recognize",
                "Removed a redundant green checkmark on completed Daily Jobs rows where the card fill already showed completion",
            ],
            commitHash: "pending"
        ),
        AppRelease(
            version: "1.1.0",
            build: "33",
            releaseDate: releaseDate(2026, 8, 10),
            updateType: .minor,
            summary: "Daily Jobs can now repeat for a staff member and be manually reordered, plus account-deletion compliance and dashboard fixes.",
            features: [
                "Daily Jobs: \"Repeat daily\" toggle per staff member — new shifts automatically get the same jobs assigned instead of requiring a fresh pick every day",
                "Daily Jobs: drag-to-reorder the jobs assigned to a shift — staff see and complete them in the order set",
                "Daily Jobs: local \"Please check your daily jobs\" reminders, roughly once an hour during a shift with incomplete jobs — fully on-device, no push notification or server round-trip involved",
                "ATO-safe account deletion flow, a staff Tax File Number field, and an in-app Terms of Service page",
            ],
            bugFixes: [
                "New shift's Publish toggle now defaults off instead of on, so a newly created shift starts as a draft until explicitly published",
                "Manager Dashboard: the four metric cards (Active Staff, Hours Scheduled, Tasks Completed, Pending Timesheets) are now a consistent height regardless of label wrapping",
                "Manager Dashboard: tapping Pending Timesheets now opens a list of exactly who's pending, instead of just showing a count",
                "Bulk timesheet approval now runs concurrently instead of sequentially, so backgrounding the app mid-batch no longer strands the not-yet-started approvals",
                "Push notifications now include the required APNs payload — previously iOS silently never displayed them",
            ],
            commitHash: "pending"
        ),
        AppRelease(
            version: "1.0.0",
            build: "31",
            releaseDate: releaseDate(2026, 8, 2),
            updateType: .minor,
            summary: "Real ATO PAYG tax calculation, bulk payslip publishing, and a payroll audit trail.",
            features: [
                "Manager Payroll: PAYG withholding auto-calculates from the ATO weekly tax table (Schedule 1) instead of manual entry, with a per-staff tax-free-threshold declaration",
                "Manager Payroll: bulk \"Publish Payslips\" — select and publish any number of staff payslips in one action instead of one at a time",
                "Manager Payroll: field-level audit trail on payslip edits — records which field changed, and the old and new values",
                "Manager Payroll: bulk \"Delete all drafts\" for a pay period",
            ],
            bugFixes: [
                "Payslip regeneration no longer recreates pay for hours from a shift that was just deleted — it now reads shifts/timesheets fresh from the server instead of a local cache that could lag behind a recent delete",
            ],
            commitHash: "pending"
        ),
        AppRelease(
            version: "1.0.0",
            build: "28",
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
