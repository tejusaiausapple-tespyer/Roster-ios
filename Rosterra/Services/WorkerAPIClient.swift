import Foundation
import FirebaseAuth

enum WorkerAPIError: LocalizedError {
    case notAuthenticated
    case server(String)
    case network

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You are not signed in."
        case .server(let message): return message
        case .network: return "Could not reach the server. Check your connection and try again."
        }
    }
}

/// Talks to the same Cloudflare Worker endpoints the web app uses for the three
/// staff-facing server operations. All requests are authenticated with the
/// Firebase ID token, exactly like the web client.
struct WorkerAPIClient {
    static let shared = WorkerAPIClient()

    private func idToken(forceRefresh: Bool = false) async throws -> String {
        guard let user = Auth.auth().currentUser else { throw WorkerAPIError.notAuthenticated }
        do {
            return try await user.getIDToken(forcingRefresh: forceRefresh)
        } catch {
            throw WorkerAPIError.notAuthenticated
        }
    }

    private func post(path: String, body: [String: Any]?, forceRefreshToken: Bool = false) async throws -> [String: Any] {
        let token = try await idToken(forceRefresh: forceRefreshToken)
        var request = URLRequest(url: AppConfig.apiBaseURL.appending(path: path), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WorkerAPIError.network
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse else { throw WorkerAPIError.network }
        guard (200..<300).contains(http.statusCode) else {
            let message = (json["error"] as? String) ?? "Request failed (\(http.statusCode))."
            throw WorkerAPIError.server(message)
        }
        return json
    }

    // MARK: - Staff endpoints

    /// POST /api/staff/availability — server enforces the trusted week lock.
    func saveAvailability(userId: String, weeklyAvailability: [String: UserAvailability]) async throws {
        var weekly: [String: Any] = [:]
        for (key, value) in weeklyAvailability {
            weekly[key] = value.asDictionary
        }
        let result = try await post(path: "api/staff/availability",
                                    body: ["userId": userId, "weeklyAvailability": weekly])
        guard result["ok"] as? Bool == true else {
            throw WorkerAPIError.server(
                (result["error"] as? String) ?? "Availability could not be saved. Please try again.")
        }
    }

    /// POST /api/complete-password-change — clears the first-login flag.
    func completePasswordChange() async throws {
        _ = try await post(path: "api/complete-password-change", body: nil, forceRefreshToken: true)
    }

    // MARK: - Manager endpoints

    /// POST /api/create-auth-user — manager-only. Creates the Firebase Auth
    /// account and returns its uid (localId). The Firestore profile doc is
    /// written by the caller (RosterRepository.createStaff), mirroring the
    /// web app's addUser flow.
    func createAuthUser(email: String, password: String) async throws -> String {
        let json = try await post(path: "api/create-auth-user",
                                  body: ["email": email, "password": password])
        guard let localId = json["localId"] as? String, !localId.isEmpty else {
            throw WorkerAPIError.server("Account was created but no user id was returned.")
        }
        return localId
    }

    // MARK: - Notification triggers (best-effort, fire-and-forget)

    /// Mirrors web notificationTriggers. `recipientIds` is required for
    /// explicit-recipient events (`job-assigned`, `payslip-generated`,
    /// `message-task` — including Tasks-tab assigns via `saveTask`). The Worker
    /// requires the caller to be a manager for these and resolves recipients
    /// from the list rather than looking anything up server-side.
    func sendNotification(event: String, shiftIds: [String]? = nil, timesheetId: String? = nil, recipientIds: [String]? = nil) async {
        var body: [String: Any] = ["event": event]
        if let shiftIds { body["shiftIds"] = shiftIds }
        if let timesheetId { body["timesheetId"] = timesheetId }
        if let recipientIds { body["recipientIds"] = recipientIds }
        _ = try? await post(path: "api/send-notification", body: body)
    }
}
