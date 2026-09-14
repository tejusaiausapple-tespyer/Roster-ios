import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

/// Shared contract between the app and the Live Activity widget extension.
/// Keep this type free of app-only models so the extension stays lightweight.
struct ShiftLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case ready
            case working
            case onBreak

            var title: String {
                switch self {
                case .ready: return "Ready to start"
                case .working: return "On shift"
                case .onBreak: return "On break"
                }
            }
        }

        var phase: Phase
        var clockInDate: Date?
        var completedJobs: Int
        var totalJobs: Int
    }

    var shiftID: String
    var companyName: String
    var location: String
    var startDate: Date
    var endDate: Date
}
#endif
