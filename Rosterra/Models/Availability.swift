import Foundation

/// Mirrors `DayAvailability` in src/types/index.ts
struct DayAvailability: Codable, Equatable, Hashable {
    var available: Bool
    var allDay: Bool
    var start: String?   // HH:mm
    var end: String?     // HH:mm

    /// Mirrors DEFAULT_DAY_AVAIL: available all day 09:00–17:00.
    static let defaultDay = DayAvailability(available: true, allDay: true, start: "09:00", end: "17:00")

    init(available: Bool, allDay: Bool, start: String? = nil, end: String? = nil) {
        self.available = available
        self.allDay = allDay
        self.start = start
        self.end = end
    }

    init(dict: [String: Any]) {
        self.available = FS.bool(dict, "available", default: true)
        self.allDay = FS.bool(dict, "allDay", default: true)
        self.start = FS.string(dict, "start")
        self.end = FS.string(dict, "end")
    }

    var asDictionary: [String: Any] {
        var d: [String: Any] = ["available": available, "allDay": allDay]
        if let start { d["start"] = start }
        if let end { d["end"] = end }
        return d
    }
}

/// The seven weekday keys used across the app, Monday-first.
enum Weekday: String, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: String { rawValue }

    var fullLabel: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var shortLabel: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
}

/// Mirrors `UserAvailability` (a fixed 7-day map).
struct UserAvailability: Codable, Equatable {
    var days: [Weekday: DayAvailability]

    init(days: [Weekday: DayAvailability]) {
        self.days = days
    }

    static var defaultAvailability: UserAvailability {
        var map: [Weekday: DayAvailability] = [:]
        for day in Weekday.allCases { map[day] = .defaultDay }
        return UserAvailability(days: map)
    }

    subscript(_ day: Weekday) -> DayAvailability {
        get { days[day] ?? .defaultDay }
        set { days[day] = newValue }
    }

    init(dict: [String: Any]) {
        var map: [Weekday: DayAvailability] = [:]
        for day in Weekday.allCases {
            if let dayDict = dict[day.rawValue] as? [String: Any] {
                map[day] = DayAvailability(dict: dayDict)
            } else {
                map[day] = .defaultDay
            }
        }
        self.days = map
    }

    var asDictionary: [String: Any] {
        var out: [String: Any] = [:]
        for day in Weekday.allCases {
            out[day.rawValue] = self[day].asDictionary
        }
        return out
    }

    // Codable conformance keyed by weekday rawValue.
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var map: [Weekday: DayAvailability] = [:]
        for day in Weekday.allCases {
            if let key = DynamicKey(stringValue: day.rawValue),
               let value = try? container.decode(DayAvailability.self, forKey: key) {
                map[day] = value
            } else {
                map[day] = .defaultDay
            }
        }
        self.days = map
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for day in Weekday.allCases {
            if let key = DynamicKey(stringValue: day.rawValue) {
                try container.encode(self[day], forKey: key)
            }
        }
    }
}
