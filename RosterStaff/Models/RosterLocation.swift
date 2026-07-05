import Foundation

/// A manager-defined work location: suburb + Australian state, with the
/// state's capital city associated automatically (editable when needed).
/// Stored as an array on the `settings/locations` document — the deployed
/// Firestore rules allow manager writes to any `settings/{docId}`, so no
/// rules change is required (there is no `locations` collection in the rules).
struct RosterLocation: Identifiable, Equatable {
    var suburb: String
    var state: String   // e.g. "SA"
    var city: String    // capital city, auto-derived from state by default

    var id: String { displayName }

    /// The string written to `shifts.location` (kept as a plain string for
    /// compatibility with the PWA's schema).
    var displayName: String { "\(suburb), \(state)" }

    static let states = ["NSW", "VIC", "QLD", "SA", "WA", "TAS", "NT", "ACT"]

    static func capital(for state: String) -> String {
        switch state {
        case "NSW": return "Sydney"
        case "VIC": return "Melbourne"
        case "QLD": return "Brisbane"
        case "SA":  return "Adelaide"
        case "WA":  return "Perth"
        case "TAS": return "Hobart"
        case "NT":  return "Darwin"
        case "ACT": return "Canberra"
        default:    return ""
        }
    }

    init(suburb: String, state: String, city: String? = nil) {
        self.suburb = suburb
        self.state = state
        self.city = city ?? Self.capital(for: state)
    }

    init?(dict: [String: Any]) {
        let suburb = FS.stringValue(dict, "suburb")
        let state = FS.stringValue(dict, "state")
        guard !suburb.isEmpty, !state.isEmpty else { return nil }
        self.suburb = suburb
        self.state = state
        self.city = FS.string(dict, "city") ?? Self.capital(for: state)
    }

    var asDictionary: [String: Any] {
        ["suburb": suburb, "state": state, "city": city]
    }
}
