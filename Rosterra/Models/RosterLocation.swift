import Foundation

/// A manager-defined work location: suburb + Australian state, with the
/// state's capital city associated automatically (editable when needed).
/// Stored as an array on the `settings/locations` document — the deployed
/// Firestore rules allow manager writes to any `settings/{docId}`, so no
/// rules change is required (there is no `locations` collection in the rules).
struct RosterLocation: Identifiable, Equatable {
    /// Fallback geofence radius when a location has coordinates but no
    /// explicit radius saved.
    static let defaultGeofenceRadius: Double = 250

    var suburb: String
    var state: String   // e.g. "SA"
    var city: String    // capital city, auto-derived from state by default
    /// Geofence anchor for shift attendance verification. Optional — locations
    /// without coordinates skip geofence checks (attendance records "unknown").
    var latitude: Double?
    var longitude: Double?
    /// Allowed distance from the anchor in metres.
    var geofenceRadius: Double?
    /// Strict enforcement: when true, staff physically outside the radius are
    /// BLOCKED from starting a shift here ("You are outside the work zone.").
    /// When false, starts are checked against a lenient 250 m allowance and
    /// out-of-zone attempts warn + record instead of blocking. Never applies
    /// to ending a shift.
    var geofenceEnforced: Bool = false

    var id: String { displayName }

    var hasGeofence: Bool { latitude != nil && longitude != nil }

    var effectiveGeofenceRadius: Double { geofenceRadius ?? Self.defaultGeofenceRadius }

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

    init(suburb: String, state: String, city: String? = nil,
         latitude: Double? = nil, longitude: Double? = nil, geofenceRadius: Double? = nil,
         geofenceEnforced: Bool = false) {
        self.suburb = suburb
        self.state = state
        self.city = city ?? Self.capital(for: state)
        self.latitude = latitude
        self.longitude = longitude
        self.geofenceRadius = geofenceRadius
        self.geofenceEnforced = geofenceEnforced
    }

    init?(dict: [String: Any]) {
        let suburb = FS.stringValue(dict, "suburb")
        let state = FS.stringValue(dict, "state")
        guard !suburb.isEmpty, !state.isEmpty else { return nil }
        self.suburb = suburb
        self.state = state
        self.city = FS.string(dict, "city") ?? Self.capital(for: state)
        self.latitude = (dict["latitude"] as? NSNumber)?.doubleValue
        self.longitude = (dict["longitude"] as? NSNumber)?.doubleValue
        self.geofenceRadius = (dict["geofenceRadius"] as? NSNumber)?.doubleValue
        self.geofenceEnforced = FS.bool(dict, "geofenceEnforced")
    }

    var asDictionary: [String: Any] {
        var dict: [String: Any] = ["suburb": suburb, "state": state, "city": city]
        if let latitude { dict["latitude"] = latitude }
        if let longitude { dict["longitude"] = longitude }
        if let geofenceRadius { dict["geofenceRadius"] = geofenceRadius }
        dict["geofenceEnforced"] = geofenceEnforced
        return dict
    }
}
