import Foundation

/// Mirrors the `settings/app` document (staff read the company name).
struct AppSettings: Equatable {
    var companyName: String

    static let fallback = AppSettings(companyName: "Sura Roster")

    init(companyName: String) {
        self.companyName = companyName
    }

    init(data: [String: Any]) {
        self.companyName = FS.string(data, "companyName") ?? "Sura Roster"
    }
}
