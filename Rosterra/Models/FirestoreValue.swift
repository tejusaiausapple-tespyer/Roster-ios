import Foundation
import FirebaseFirestore

/// Helpers for safely reading loosely-typed Firestore document dictionaries.
///
/// The backend stores several fields with mixed representations (e.g. a value that
/// may be a Firestore `Timestamp`, an ISO-8601 `String`, or a `Date`). These helpers
/// centralise the coercion so model initialisers stay readable, matching the tolerant
/// parsing the web app performs (see `toIsoDateTime` / `isShiftSubmittable`).
enum FS {
    static func string(_ dict: [String: Any], _ key: String) -> String? {
        if let s = dict[key] as? String { return s }
        return nil
    }

    static func stringValue(_ dict: [String: Any], _ key: String, default def: String = "") -> String {
        string(dict, key) ?? def
    }

    static func bool(_ dict: [String: Any], _ key: String, default def: Bool = false) -> Bool {
        bool(any: dict[key], default: def)
    }

    /// Firestore often surfaces booleans as `NSNumber` rather than Swift `Bool`.
    static func bool(any value: Any?, default def: Bool = false) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return def
    }

    static func int(_ dict: [String: Any], _ key: String, default def: Int = 0) -> Int {
        if let i = dict[key] as? Int { return i }
        if let n = dict[key] as? NSNumber { return n.intValue }
        if let d = dict[key] as? Double { return Int(d) }
        return def
    }

    static func double(_ dict: [String: Any], _ key: String, default def: Double = 0) -> Double {
        if let d = dict[key] as? Double { return d }
        if let n = dict[key] as? NSNumber { return n.doubleValue }
        if let i = dict[key] as? Int { return Double(i) }
        return def
    }

    /// Coerce a Firestore `Timestamp`, `Date`, or ISO-8601 string into a `Date`.
    static func date(_ dict: [String: Any], _ key: String) -> Date? {
        return date(any: dict[key])
    }

    static func date(any value: Any?) -> Date? {
        guard let value else { return nil }
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let d = value as? Date { return d }
        if let s = value as? String { return isoDate(from: s) }
        return nil
    }

    /// Coerce a Firestore value to its ISO-8601 string form (mirrors `toIsoDateTime`).
    static func isoString(_ dict: [String: Any], _ key: String) -> String? {
        if let s = dict[key] as? String { return s }
        if let ts = dict[key] as? Timestamp { return isoFormatter.string(from: ts.dateValue()) }
        if let d = dict[key] as? Date { return isoFormatter.string(from: d) }
        return nil
    }

    static func stringMap(_ dict: [String: Any], _ key: String) -> [String: Any]? {
        dict[key] as? [String: Any]
    }

    // MARK: - ISO helpers

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func isoDate(from string: String) -> Date? {
        if let d = isoFormatter.date(from: string) { return d }
        // Fallback without fractional seconds
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
