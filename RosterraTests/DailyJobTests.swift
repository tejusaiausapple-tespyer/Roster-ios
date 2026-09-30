import XCTest
@testable import Rosterra

final class DailyJobTests: XCTestCase {

    private func makeAssignment(date: String) -> DailyJobAssignment {
        DailyJobAssignment(
            id: "s1_t1", shiftId: "s1", staffId: "u1", templateId: "t1",
            title: "Wash floors", date: date, assignedAt: nil, assignedBy: nil,
            completed: false, completedAt: nil, completedBy: nil, order: nil
        )
    }

    func testDocIdIsDeterministicPerShiftAndTemplate() {
        XCTAssertEqual(DailyJobAssignment.docId(shiftId: "s1", templateId: "t1"), "s1_t1")
    }

    func testVisibleForEntireShiftDate() {
        let now = Date()
        let today = makeAssignment(date: RosterCalendar.todayKey(now))
        XCTAssertTrue(today.isVisibleToStaff(now: now))

        let yesterday = makeAssignment(date: RosterCalendar.todayKey(RosterCalendar.addDays(-1, to: now)))
        XCTAssertFalse(yesterday.isVisibleToStaff(now: now))
    }

    func testHiddenAfterCalendarDayEnds() {
        let now = Date()
        let todayKey = RosterCalendar.todayKey(now)
        let assignment = makeAssignment(date: todayKey)
        // Still visible after rostered shift end — window is the full calendar day.
        XCTAssertTrue(assignment.isVisibleToStaff(now: now))
    }

    // MARK: - Native OCC & Count-Race Tests

    func testOCCVersionVerificationSucceedsOnMatchAndThrowsOnMismatch() {
        // Baseline version matches current version
        XCTAssertNoThrow(try DailyJobOCCLogic.verifyVersion(baseline: 2, current: 2))

        // Baseline version differs from current version -> OCC mismatch
        XCTAssertThrowsError(try DailyJobOCCLogic.verifyVersion(baseline: 2, current: 3)) { error in
            XCTAssertEqual(error as? DailyJobOCCError, DailyJobOCCError.versionMismatch(expected: 2, actual: 3))
        }
    }

    func testModernShiftCompletionSkipsCountQuery() throws {
        // Modern shift already has dailyJobsCount = 4
        // resolveCountForCompletion must return existing count without requiring server count
        let resolved = try DailyJobOCCLogic.resolveCountForCompletion(
            shiftCount: 4,
            authoritativeServerCount: nil,
            expectedVersion: nil,
            currentVersion: 2
        )
        XCTAssertEqual(resolved, 4, "Modern shift must use existing dailyJobsCount without fetching server count")
    }

    func testLegacyShiftRequiresCountInitialization() {
        // Legacy shift has dailyJobsCount = nil. Without authoritative server count, throws preconditionRequired
        XCTAssertThrowsError(
            try DailyJobOCCLogic.resolveCountForCompletion(
                shiftCount: nil,
                authoritativeServerCount: nil,
                expectedVersion: nil,
                currentVersion: 0
            )
        ) { error in
            XCTAssertEqual(error as? DailyJobOCCError, DailyJobOCCError.preconditionRequired(currentVersion: 0))
        }

        // Once authoritative server count is provided at expected version, succeeds and initializes count
        let resolved = try? DailyJobOCCLogic.resolveCountForCompletion(
            shiftCount: nil,
            authoritativeServerCount: 3,
            expectedVersion: 0,
            currentVersion: 0
        )
        XCTAssertEqual(resolved, 3)
    }

    func testConcurrentAssignmentChangeDuringCountInitializationThrowsOCCMismatch() {
        // Legacy shift: client reads version 1, triggers server count fetch (count = 2)
        // Meanwhile, concurrent client writes an assignment and advances shift version to 2
        XCTAssertThrowsError(
            try DailyJobOCCLogic.resolveCountForCompletion(
                shiftCount: nil,
                authoritativeServerCount: 2,
                expectedVersion: 1,
                currentVersion: 2
            )
        ) { error in
            XCTAssertEqual(error as? DailyJobOCCError, DailyJobOCCError.versionMismatch(expected: 1, actual: 2))
        }

        // On retry with fresh server count (3) and matching version (2), succeeds
        let retryResolved = try? DailyJobOCCLogic.resolveCountForCompletion(
            shiftCount: nil,
            authoritativeServerCount: 3,
            expectedVersion: 2,
            currentVersion: 2
        )
        XCTAssertEqual(retryResolved, 3)
    }

    func testConcurrentInitializationAdoptsPersistedCount() throws {
        // Client A and Client B race to initialize legacy shift count.
        // Client A fetched count = 2 at version 0.
        // Client B committed first, writing shiftCount = 2 and advancing version to 1.
        // When Client A enters transaction, shiftDoc now has shiftCount = 2.
        let resolved = try DailyJobOCCLogic.resolveCountForCompletion(
            shiftCount: 2,
            authoritativeServerCount: 2,
            expectedVersion: 0,
            currentVersion: 1
        )
        XCTAssertEqual(resolved, 2, "Must adopt the server's persisted count rather than failing or overwriting")
    }

    func testSaveCountExcludesUnavailableTemplates() {
        // Manager selected 3 template IDs: ["t1", "t2", "deleted_template"]
        // Only ["t1", "t2"] exist in the manager's library
        let requested = ["t1", "t2", "deleted_template"]
        let available: Set<String> = ["t1", "t2"]
        let existing: [DailyJobAssignment] = []

        let (newlyAdded, finalCount) = DailyJobOCCLogic.computeSaveCount(
            requestedTemplateIds: requested,
            availableTemplateIds: available,
            existingAssignments: existing
        )

        XCTAssertEqual(newlyAdded, 2, "Unavailable templates must not be counted as newly added")
        XCTAssertEqual(finalCount, 2, "Final count must reflect only the available templates")
    }

    func testSaveCountWithRetainedAndNewlyAddedAssignments() {
        let requested = ["t1", "t2", "t3"]
        let available: Set<String> = ["t1", "t2", "t3"]
        let existing = [
            DailyJobAssignment(
                id: "s1_t1", shiftId: "s1", staffId: "u1", templateId: "t1",
                title: "Job 1", date: "2026-06-01", assignedAt: nil, assignedBy: nil,
                completed: false, completedAt: nil, completedBy: nil, order: 0
            )
        ]

        let (newlyAdded, finalCount) = DailyJobOCCLogic.computeSaveCount(
            requestedTemplateIds: requested,
            availableTemplateIds: available,
            existingAssignments: existing
        )

        XCTAssertEqual(newlyAdded, 2, "t2 and t3 are new")
        XCTAssertEqual(finalCount, 3, "t1 retained + t2 and t3 added = 3 total")
    }

    func testReorderModernShiftPreservesCountWithoutQuery() throws {
        let resolved = try DailyJobOCCLogic.resolveCountForReorder(
            shiftCount: 5,
            authoritativeServerCount: nil,
            expectedVersion: nil,
            currentVersion: 3
        )
        XCTAssertEqual(resolved, 5, "Reorder on modern shift must preserve existing count without server read")
    }

    func testReorderLegacyShiftRequiresAuthoritativeServerCountAndRejectsLocalFallback() {
        // Without authoritative count, legacy reorder must fail closed (throwing preconditionRequired)
        // rather than guessing orderedAssignmentIds.count
        XCTAssertThrowsError(
            try DailyJobOCCLogic.resolveCountForReorder(
                shiftCount: nil,
                authoritativeServerCount: nil,
                expectedVersion: nil,
                currentVersion: 0
            )
        ) { error in
            XCTAssertEqual(error as? DailyJobOCCError, DailyJobOCCError.preconditionRequired(currentVersion: 0))
        }

        // With authoritative count (e.g. 4), returns authoritative count
        let resolved = try? DailyJobOCCLogic.resolveCountForReorder(
            shiftCount: nil,
            authoritativeServerCount: 4,
            expectedVersion: 0,
            currentVersion: 0
        )
        XCTAssertEqual(resolved, 4)

        // If version mismatch occurred during count fetch, throws versionMismatch
        XCTAssertThrowsError(
            try DailyJobOCCLogic.resolveCountForReorder(
                shiftCount: nil,
                authoritativeServerCount: 4,
                expectedVersion: 0,
                currentVersion: 1
            )
        ) { error in
            XCTAssertEqual(error as? DailyJobOCCError, DailyJobOCCError.versionMismatch(expected: 0, actual: 1))
        }
    }

    func testTwoConsecutiveConcurrentAssignmentChangesExercisesRetryMethod() async throws {
        // Shift starts as legacy (count = nil, version = 0).
        // Assignments in DB: initially 2.
        var shiftVersion = 0
        var shiftCount: Int? = nil
        var assignmentsInDB = 2

        var attemptsExecuted = 0
        var freshTokensCaptured: [Int] = []
        var countsQueried: [Int] = []
        var expectedVersionsChecked: [Int?] = []

        try await DailyJobOCCLogic.executeCompletionRetry(
            maxAttempts: 5,
            runTransactionAttempt: { authoritativeCount, expectedVersion in
                attemptsExecuted += 1
                expectedVersionsChecked.append(expectedVersion)

                let currentVer = shiftVersion
                let existingCount = shiftCount

                // Resolve count: throws preconditionRequired if nil, throws versionMismatch if mismatch
                let finalCount: Int
                do {
                    finalCount = try DailyJobOCCLogic.resolveCountForCompletion(
                        shiftCount: existingCount,
                        authoritativeServerCount: authoritativeCount,
                        expectedVersion: expectedVersion,
                        currentVersion: currentVer
                    )
                } catch DailyJobOCCError.preconditionRequired(let ver) {
                    throw NSError(domain: "Rosterra", code: 428, userInfo: ["version": ver])
                } catch DailyJobOCCError.versionMismatch(let exp, let act) {
                    throw NSError(domain: "Rosterra", code: 409, userInfo: [NSLocalizedDescriptionKey: "OCC mismatch: exp \(exp), act \(act)"])
                }

                // Transaction succeeds:
                shiftVersion = currentVer + 1
                shiftCount = finalCount
            },
            fetchFreshServerToken: {
                freshTokensCaptured.append(shiftVersion)
                return shiftVersion
            },
            fetchAuthoritativeServerCount: {
                countsQueried.append(assignmentsInDB)
                let countToReturn = assignmentsInDB

                if attemptsExecuted == 1 {
                    // Race 1: While Attempt 1's count was fetched,
                    // Concurrent Client 1 inserts an assignment, advancing shift version to 1.
                    shiftVersion = 1
                    assignmentsInDB = 3
                } else if attemptsExecuted == 2 {
                    // Race 2: After Attempt 2's replacement count query was performed,
                    // Concurrent Client 2 inserts ANOTHER assignment, advancing shift version to 2!
                    shiftVersion = 2
                    assignmentsInDB = 4
                }

                return countToReturn
            }
        )

        // Verify that:
        // 1. Exactly 4 attempts ran before success (Attempt 1: 428, Attempt 2: 409, Attempt 3: 409, Attempt 4: commit)
        XCTAssertEqual(attemptsExecuted, 4)

        // 2. Expected versions checked across the 4 attempts:
        // Attempt 1: nil (uninitialized legacy shift)
        // Attempt 2: 0 (from Attempt 1 count fetch; rejected because shiftVersion became 1)
        // Attempt 3: 1 (from fresh token captured on 409; rejected because shiftVersion became 2 after replacement query)
        // Attempt 4: 2 (from second fresh token captured on 409; matched shiftVersion = 2!)
        XCTAssertEqual(expectedVersionsChecked, [nil, 0, 1, 2])

        // 3. Crucial requirement: NEVER retry with expectedVersion = nil!
        // Attempts 2, 3, 4 all had non-nil expected versions!
        XCTAssertFalse(expectedVersionsChecked.dropFirst().contains(nil), "Retries must NEVER have expectedVersion = nil")

        // 4. Fresh tokens captured on the two 409 version mismatches:
        XCTAssertEqual(freshTokensCaptured, [1, 2], "Must capture fresh server token (1 then 2) before requerying count")

        // 5. Final shift state:
        XCTAssertEqual(shiftCount, 4, "Final count must be 4 reflecting all concurrent additions")
        XCTAssertEqual(shiftVersion, 3, "Final version must be 3 (version was 2 when Attempt 4 ran, incremented to 3)")
    }
}
