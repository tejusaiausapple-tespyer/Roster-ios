import Foundation

/// Australian Tax File Number helpers.
/// Algorithm: 9 digits, weighted sum mod 11 == 0 (weights 1,4,3,7,5,8,6,9,10).
enum TFN {
    private static let weights = [1, 4, 3, 7, 5, 8, 6, 9, 10]

    static func normalize(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(9))
    }

    static func isValid(_ raw: String) -> Bool {
        let digits = normalize(raw)
        guard digits.count == 9 else { return false }
        if Set(digits).count == 1 { return false }
        var sum = 0
        for (i, ch) in digits.enumerated() {
            guard let d = Int(String(ch)) else { return false }
            sum += d * weights[i]
        }
        return sum % 11 == 0
    }

    /// XXX XXX XXX
    static func format(_ raw: String) -> String {
        let d = normalize(raw)
        var parts: [String] = []
        if d.count > 0 { parts.append(String(d.prefix(3))) }
        if d.count > 3 { parts.append(String(d.dropFirst(3).prefix(3))) }
        if d.count > 6 { parts.append(String(d.dropFirst(6).prefix(3))) }
        return parts.joined(separator: " ")
    }

    /// *** *** 123
    static func mask(_ raw: String?) -> String {
        let d = normalize(raw ?? "")
        guard d.count >= 3 else { return d.isEmpty ? "—" : "•••" }
        return "*** *** \(d.suffix(3))"
    }

    static func last4(_ raw: String?) -> String {
        let d = normalize(raw ?? "")
        guard d.count >= 4 else { return "" }
        return String(d.suffix(4))
    }

    /// Empty allowed; non-empty must be valid.
    static func validationError(_ raw: String) -> String? {
        let d = normalize(raw)
        if d.isEmpty { return nil }
        if d.count != 9 { return "TFN must be 9 digits" }
        if !isValid(d) { return "Enter a valid Australian TFN" }
        return nil
    }
}
