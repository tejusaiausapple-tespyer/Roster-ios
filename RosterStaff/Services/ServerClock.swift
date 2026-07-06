import Foundation

/// Trusted wall-clock time, independent of the device's (user-changeable) clock.
///
/// The offset is measured from the `Date` header of an HTTPS response from
/// Google's Firestore front-end — the same infrastructure that stamps the
/// authoritative `FieldValue.serverTimestamp()` values on attendance records.
/// TLS prevents spoofing the header without also breaking the app's Firebase
/// traffic. The offset is re-measured on login and every foreground activation.
///
/// `now` falls back to the device clock until the first sync completes
/// (offline first launch); callers that gate actions on time should treat
/// that as acceptable-but-unverified, mirroring the attendance model.
@MainActor
final class ServerClock {
    static let shared = ServerClock()

    /// serverTime - deviceTime, in seconds. 0 until first sync.
    private(set) var offset: TimeInterval = 0
    private(set) var isSynced = false
    private var isSyncing = false

    private static let probeURL = URL(string: "https://firestore.googleapis.com/")!

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    /// Best-available current time: server-corrected when synced.
    var now: Date { Date().addingTimeInterval(offset) }

    /// Measure the device-vs-server offset. Cheap (HEAD request); safe to call
    /// on every activation. No-ops while a sync is already in flight.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var request = URLRequest(url: Self.probeURL)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 10

        let before = Date()
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "Date"),
              let serverDate = Self.headerFormatter.date(from: header) else { return }
        let after = Date()

        // Assume the header was stamped mid-flight; sub-second accuracy is
        // plenty for a 5-minute gate (the authoritative record still uses
        // Firestore serverTimestamp()).
        let midpoint = before.addingTimeInterval(after.timeIntervalSince(before) / 2)
        offset = serverDate.timeIntervalSince(midpoint)
        isSynced = true
    }
}
