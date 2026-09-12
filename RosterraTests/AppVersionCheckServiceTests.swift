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

    // MARK: - AppVersionCheck.evaluate — up to date

    func testUpToDateWhenInstalledMatchesLatest() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.2.0",
            latestVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .upToDate)
    }

    func testUpToDateWhenInstalledIsNewerThanLatest() {
        // e.g. a TestFlight build ahead of the published Remote Config value.
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.3.0",
            latestVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .upToDate)
    }

    // MARK: - AppVersionCheck.evaluate — optional update (patch-only gap)

    func testOptionalUpdateWhenOnlyPatchBehindLatest() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.2.0",
            latestVersion: "1.2.3",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .optional(latestVersion: "1.2.3"))
    }

    // MARK: - AppVersionCheck.evaluate — required update

    func testRequiredUpdateWhenBelowMinimum() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "0.9.0",
            latestVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .required(minimumVersion: "1.0.0"))
    }

    func testRequiredUpdateWhenMinorBehindLatest() {
        // Minor gap — not patch-only — is mandatory even without the force flag.
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.1.0",
            latestVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .required(minimumVersion: "1.2.0"))
    }

    func testRequiredUpdateWhenMajorBehindLatest() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.9.9",
            latestVersion: "2.0.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .required(minimumVersion: "2.0.0"))
    }

    func testRequiredUpdateWhenForceUpdateFlagSetEvenForPatchOnlyGap() {
        // Kill switch: force everyone below `latest`, even a patch-only gap
        // that would otherwise be skippable.
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.2.0",
            latestVersion: "1.2.3",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: true
        )
        XCTAssertEqual(status, .required(minimumVersion: "1.2.3"))
    }

    func testForceUpdateFlagIsNoOpWhenAlreadyOnLatest() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.2.0",
            latestVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: true
        )
        XCTAssertEqual(status, .upToDate)
    }

    // MARK: - AppVersionCheck.evaluate — fail-open on bad data

    func testFailsOpenWhenInstalledVersionUnparseable() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "not-a-version",
            latestVersion: "1.2.0",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: true
        )
        XCTAssertEqual(status, .upToDate)
    }

    func testIgnoresUnparseableMinimumVersion() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.0.0",
            latestVersion: "1.0.0",
            minimumSupportedVersion: "not-a-version",
            forceUpdate: false
        )
        XCTAssertEqual(status, .upToDate)
    }

    func testIgnoresUnparseableLatestVersion() {
        let status = AppVersionCheck.evaluate(
            installedVersion: "1.0.0",
            latestVersion: "not-a-version",
            minimumSupportedVersion: "1.0.0",
            forceUpdate: false
        )
        XCTAssertEqual(status, .upToDate)
    }
}
