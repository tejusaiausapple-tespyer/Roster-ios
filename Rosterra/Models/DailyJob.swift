import Foundation
import FirebaseFirestore

/// Daily Jobs are separate from Tasks: managers keep a permanent library of
/// reusable job templates and assign a selection to a specific staff member's
/// specific shift. Staff see assignments for the full shift date; templates never do.
/// See docs/daily-jobs-feature.md.
struct DailyJobTemplate: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let active: Bool
    let createdAt: Date?
    let createdBy: String?
}

/// One job assigned to one shift. Doc ID is "{shiftId}_{templateId}" so
/// re-assigning the same job to the same shift is idempotent.
struct DailyJobAssignment: Identifiable, Codable {
    var id: String
    let shiftId: String
    let staffId: String
    let templateId: String
    let title: String        // snapshot — template edits don't rewrite history
    let date: String         // shift date (yyyy-MM-dd), for windowed queries
    let assignedAt: Date?
    let assignedBy: String?
    let completed: Bool
    let completedAt: Date?
    let completedBy: String?
    /// Manager-arranged position within the shift — the order staff should
    /// work through the jobs in. `nil` on assignments written before this
    /// field existed; those sort after any explicitly-ordered ones.
    let order: Int?

    static func docId(shiftId: String, templateId: String) -> String {
        "\(shiftId)_\(templateId)"
    }

    /// Staff see an assignment for the full shift date (Adelaide calendar day),
    /// not just until rostered end time. Manager history keeps it forever.
    func isVisibleToStaff(now: Date = Date()) -> Bool {
        date == RosterCalendar.todayKey(now)
    }
}

/// One staff member's "keep repeating these jobs" preference. Doc ID is the
/// staffId (one rule per staff member). When `enabled`, every new shift
/// created for this staff member auto-gets `templateIds` assigned — the
/// manager no longer has to re-pick jobs each day. Disabling keeps
/// `templateIds` around so re-enabling doesn't lose the previous selection;
/// it only stops new shifts from being auto-populated.
struct DailyJobRepeatRule: Identifiable, Codable {
    @DocumentID var id: String?
    let templateIds: [String]
    let enabled: Bool
    let updatedAt: Date?
    let updatedBy: String?
}

/// Errors occurring during optimistic concurrency control (OCC) or count-race resolution.
enum DailyJobOCCError: LocalizedError, Equatable {
    case preconditionRequired(currentVersion: Int)
    case versionMismatch(expected: Int, actual: Int)
    case shiftNotFound

    var errorDescription: String? {
        switch self {
        case .preconditionRequired(let currentVersion):
            return "Legacy shift requires server count initialization (version: \(currentVersion))."
        case .versionMismatch(let expected, let actual):
            return "OCC version mismatch: expected \(expected), actual \(actual)."
        case .shiftNotFound:
            return "Shift not found."
        }
    }
}

/// Pure OCC logic and race resolution for Daily Jobs mutations across iOS, ensuring
/// deterministic behavior that can be tested without mock network overhead.
enum DailyJobOCCLogic {

    /// Calculates newly added count and total final count for shift saving,
    /// correctly excluding unavailable/deleted templates.
    static func computeSaveCount(
        requestedTemplateIds: [String],
        availableTemplateIds: Set<String>,
        existingAssignments: [DailyJobAssignment]
    ) -> (newlyAddedCount: Int, finalCount: Int) {
        var newlyAddedCount = 0
        for templateId in requestedTemplateIds {
            if !existingAssignments.contains(where: { $0.templateId == templateId }) &&
                availableTemplateIds.contains(templateId) {
                newlyAddedCount += 1
            }
        }
        let retainedCount = existingAssignments.filter { requestedTemplateIds.contains($0.templateId) }.count
        let finalCount = retainedCount + newlyAddedCount
        return (newlyAddedCount, finalCount)
    }

    /// Resolves the shift's `dailyJobsCount` for an assignment completion write.
    /// - Modern shifts (count already on shift doc): returns existing count immediately (0 query reads).
    /// - Legacy shifts (count absent): throws .preconditionRequired if authoritativeServerCount is nil.
    /// - Race protection: If expectedVersion does not match currentVersion, throws .versionMismatch so caller retries.
    /// - Concurrent init protection: If shiftCount is now populated (another client initialized it concurrently), uses shiftCount.
    static func resolveCountForCompletion(
        shiftCount: Int?,
        authoritativeServerCount: Int?,
        expectedVersion: Int?,
        currentVersion: Int
    ) throws -> Int {
        if let expectedVersion, currentVersion != expectedVersion {
            throw DailyJobOCCError.versionMismatch(expected: expectedVersion, actual: currentVersion)
        }
        if let shiftCount {
            return shiftCount
        }
        guard let authoritativeServerCount else {
            throw DailyJobOCCError.preconditionRequired(currentVersion: currentVersion)
        }
        return max(1, authoritativeServerCount)
    }

    /// Resolves the shift's `dailyJobsCount` for a reorder write.
    /// - Never falls back to `orderedAssignmentIds.count` when absent.
    /// - Modern shifts: returns existing count (0 query reads).
    /// - Legacy shifts: requires authoritative server count, protected against concurrent version mismatch.
    static func resolveCountForReorder(
        shiftCount: Int?,
        authoritativeServerCount: Int?,
        expectedVersion: Int?,
        currentVersion: Int
    ) throws -> Int {
        if let expectedVersion, currentVersion != expectedVersion {
            throw DailyJobOCCError.versionMismatch(expected: expectedVersion, actual: currentVersion)
        }
        if let shiftCount {
            return shiftCount
        }
        guard let authoritativeServerCount else {
            throw DailyJobOCCError.preconditionRequired(currentVersion: currentVersion)
        }
        return authoritativeServerCount
    }

    /// Verifies that the current version matches baseline version.
    static func verifyVersion(baseline: Int, current: Int) throws {
        guard baseline == current else {
            throw DailyJobOCCError.versionMismatch(expected: baseline, actual: current)
        }
    }

    /// Executes the full OCC retry loop for completing a daily job assignment on a shift.
    /// Handles legacy count initialization (HTTP 428), captures fresh server token on version mismatch (HTTP 409)
    /// BEFORE requerying count, never retries with expectedVersion == nil, and compares expectedVersion in the next transaction.
    static func executeCompletionRetry(
        maxAttempts: Int = 5,
        runTransactionAttempt: (_ authoritativeCount: Int?, _ expectedVersion: Int?) async throws -> Void,
        fetchFreshServerToken: () async throws -> Int,
        fetchAuthoritativeServerCount: () async throws -> Int
    ) async throws {
        var authoritativeCount: Int?
        var expectedVersion: Int?

        for attempt in 1...maxAttempts {
            do {
                try await runTransactionAttempt(authoritativeCount, expectedVersion)
                return
            } catch let error as NSError where error.code == 428 && attempt < maxAttempts {
                let currentVer = error.userInfo["version"] as? Int ?? 0
                authoritativeCount = try await fetchAuthoritativeServerCount()
                expectedVersion = currentVer
                continue
            } catch let error as NSError where error.code == 409 && attempt < maxAttempts {
                // 1. Capture a fresh server token BEFORE requerying the count:
                let freshVer = try await fetchFreshServerToken()
                // 2. Requery the count:
                authoritativeCount = try await fetchAuthoritativeServerCount()
                // 3. Set expectedVersion to the fresh server token (NEVER nil!):
                expectedVersion = freshVer
                // 4. In the next transaction attempt, currentVer will be compared to this expectedVersion.
                continue
            }
        }
    }
}
