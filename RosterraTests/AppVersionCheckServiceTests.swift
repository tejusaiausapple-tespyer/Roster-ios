import XCTest
@testable import Rosterra

final class AppVersionCheckServiceTests: XCTestCase {

    // MARK: - SemanticVersion parsing

    func testParsesFullVersion() {
        let v = SemanticVersion("1.2.3")
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
    }

    func testMissingComponentsDefaultToZero() {
        XCTAssertEqual(SemanticVersion("2"), SemanticVersion("2.0.0"))
        XCTAssertEqual(SemanticVersion("2.5"), SemanticVersion("2.5.0"))
    }

    func testIgnoresPrereleaseSuffix() {
        XCTAssertEqual(SemanticVersion("1.2.3-beta.1"), SemanticVersion("1.2.3"))
    }

    func testRejectsNonNumericComponents() {
        XCTAssertNil(SemanticVersion("1.x.0"))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion(""))
    }

    // MARK: - SemanticVersion ordering

    func testOrderingAcrossComponents() {
        XCTAssertLessThan(SemanticVersion("1.0.0")!, SemanticVersion("1.0.1")!)
        XCTAssertLessThan(SemanticVersion("1.0.9")!, SemanticVersion("1.1.0")!)
        XCTAssertLessThan(SemanticVersion("1.9.9")!, SemanticVersion("2.0.0")!)
        XCTAssertEqual(SemanticVersion("1.2.3")!, SemanticVersion("1.2.3")!)
        XCTAssertGreaterThan(SemanticVersion("1.10.0")!, SemanticVersion("1.9.0")!) // numeric, not lexicographic
    }

    // MARK: - Hybrid evaluate — up to date

    func testUpToDateWhenInstalledMatchesAppStore() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.2.0",
            appStoreVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .upToDate)
    }

    func testUpToDateWhenInstalledIsNewerThanAppStore() {
        // TestFlight / internal build ahead of the public Store listing.
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.3.0",
            appStoreVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .upToDate)
    }

    func testUpToDateWhenForceUpdateButAlreadyOnAppStoreVersion() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.2.0",
            appStoreVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: true
        )
        XCTAssertEqual(status, .upToDate)
    }

    // MARK: - Hybrid evaluate — optional

    func testOptionalWhenBehindAppStoreButAboveFloor() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.2.0",
            appStoreVersion: "1.2.3",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .optional(latestVersion: "1.2.3"))
    }

    func testOptionalWhenMinorBehindAppStoreWithoutForce() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.1.0",
            appStoreVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .optional(latestVersion: "1.2.0"))
    }

    // MARK: - Hybrid evaluate — required

    func testRequiredWhenBelowMinimumAndAppStoreReachable() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "0.9.0",
            appStoreVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .required(minimumVersion: "1.0.0"))
    }

    func testRequiredWhenForceUpdateAndBehindAppStore() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.2.0",
            appStoreVersion: "1.2.3",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: true
        )
        XCTAssertEqual(status, .required(minimumVersion: "1.2.3"))
    }

    func testRequiredWhenAppleUnavailableButBelowFirebaseFloor() {
        // Apple outage must not disable the hard floor.
        let status = AppVersionCheck.evaluate(
            installedVersion: "0.9.0",
            appStoreVersion: nil,
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .required(minimumVersion: "1.0.0"))
    }

    func testDoesNotRequireUnreachableFirebaseFloorAheadOfAppStore() {
        // Floor 1.3.0 but Store still shows 1.2.0 — don't lock users out.
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.1.0",
            appStoreVersion: "1.2.0",
            minimumSupportedVersion: "1.3.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .optional(latestVersion: "1.2.0"))
    }

    func testForceUpdateUsesAppStoreWhenFloorIsUnreachable() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.1.0",
            appStoreVersion: "1.2.0",
            minimumSupportedVersion: "1.3.0",
            forceUpdate: true
        )
        XCTAssertEqual(status, .required(minimumVersion: "1.2.0"))
    }

    // MARK: - Hybrid evaluate — fail-open

    func testFailsOpenWhenInstalledVersionUnparseable() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "not-a-version",
            appStoreVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: true
        )
        XCTAssertEqual(status, .upToDate)
    }

    func testIgnoresUnparseableMinimumVersion() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.0.0",
            appStoreVersion: "1.0.0",
            minimumSupportedVersion: "not-a-version",
            forceUpdate: false
        )
        XCTAssertEqual(status, .upToDate)
    }

    func testAppleFailureAloneDoesNotBlockWhenAboveFloor() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.1.0",
            appStoreVersion: nil,
            minimumSupportedVersion: "1.0.0",
            forceUpdate: true
        )
        XCTAssertEqual(status, .upToDate)
    }

    func testMalformedAppStoreVersionTreatedAsUnavailable() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.0.0",
            appStoreVersion: "not-a-version",
            minimumSupportedVersion: "0.0.0",
            forceUpdate: true
        )
        XCTAssertEqual(status, .upToDate)
    }

    // MARK: - Legacy Remote Config–only (Mac path)

    func testRemoteConfigOnlyRequiredOnMinorGap() {
        let status = AppVersionCheck.evaluateRemoteConfigOnly(
            installedVersion: "1.1.0",
            latestVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .required(minimumVersion: "1.2.0"))
    }

    func testRemoteConfigOnlyOptionalOnPatchGap() {
        let status = AppVersionCheck.evaluateRemoteConfigOnly(
            installedVersion: "1.2.0",
            latestVersion: "1.2.3",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .optional(latestVersion: "1.2.3"))
    }

    // MARK: - App Store lookup decoding

    func testDecodesAppStoreLookupResponse() throws {
        let json = """
        {"resultCount":1,"results":[{"version":"1.2.2","trackId":6791077796}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppStoreLookupResponse.self, from: json)
        XCTAssertEqual(decoded.latestVersion, "1.2.2")
    }

    func testAppStoreLookupEmptyResultsYieldsNil() throws {
        let json = """
        {"resultCount":0,"results":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppStoreLookupResponse.self, from: json)
        XCTAssertNil(decoded.latestVersion)
    }
}

// MARK: - Stub helpers

private final class StubAppVersionChecker: AppVersionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [AppUpdateStatus]
    private let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(results: [AppUpdateStatus], delayNanoseconds: UInt64 = 0) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func checkForUpdate() async -> AppUpdateStatus {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
        if results.isEmpty { return .upToDate }
        if results.count == 1 { return results[0] }
        return results.removeFirst()
    }
}

private struct StubAppStoreLookup: AppStoreVersionLooking {
    let version: String?

    func fetchLatestVersion() async -> String? {
        version
    }
}

final class AppVersionCheckViewModelTests: XCTestCase {

    @MainActor
    func testRequiredStatusSetsIsUpdateRequired() async {
        let stub = StubAppVersionChecker(results: [.required(minimumVersion: "1.2.0")])
        let vm = AppVersionCheckViewModel(service: stub)
        await vm.check()
        XCTAssertTrue(vm.isUpdateRequired)
        XCTAssertFalse(vm.isUpdateAvailable)
    }

    @MainActor
    func testOptionalStatusSetsIsUpdateAvailableUntilDismissed() async {
        let stub = StubAppVersionChecker(results: [.optional(latestVersion: "1.2.3")])
        let vm = AppVersionCheckViewModel(service: stub)
        await vm.check()
        XCTAssertTrue(vm.isUpdateAvailable)
        vm.dismissOptionalUpdate()
        XCTAssertFalse(vm.isUpdateAvailable)
    }

    @MainActor
    func testOverlappingChecksRunTrailingRecheck() async {
        let stub = StubAppVersionChecker(
            results: [
                .optional(latestVersion: "1.2.1"),
                .required(minimumVersion: "1.2.2"),
            ],
            delayNanoseconds: 30_000_000
        )
        let vm = AppVersionCheckViewModel(service: stub)

        let first = Task { await vm.check() }
        try? await Task.sleep(nanoseconds: 5_000_000)
        await vm.check()
        await first.value

        XCTAssertEqual(stub.callCount, 2)
        XCTAssertEqual(vm.status, .required(minimumVersion: "1.2.2"))
        XCTAssertTrue(vm.isUpdateRequired)
    }

    @MainActor
    func testFreshCheckCanClearRequiredAfterRollback() async {
        let stub = StubAppVersionChecker(results: [
            .required(minimumVersion: "1.2.0"),
            .upToDate,
        ])
        let vm = AppVersionCheckViewModel(service: stub)
        await vm.check()
        XCTAssertTrue(vm.isUpdateRequired)
        await vm.check()
        XCTAssertFalse(vm.isUpdateRequired)
        XCTAssertEqual(vm.status, .upToDate)
    }
}

final class AppStoreVersionLookingTests: XCTestCase {
    func testStubLookupReturnsConfiguredVersion() async {
        let lookup = StubAppStoreLookup(version: "1.2.2")
        let version = await lookup.fetchLatestVersion()
        XCTAssertEqual(version, "1.2.2")
    }

    func testStubLookupCanFailOpen() async {
        let lookup = StubAppStoreLookup(version: nil)
        let version = await lookup.fetchLatestVersion()
        XCTAssertNil(version)
    }
}
