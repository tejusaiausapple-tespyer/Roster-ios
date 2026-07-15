import XCTest
@testable import Rosterra

/// Exhaustive truth table for the RootView routing decision. This locks in
/// the Milestone 3 fix: forced-password-change and device-auth gates apply to
/// managers as well as staff (previously the manager branch was checked first
/// and skipped every gate).
final class AppRouteTests: XCTestCase {

    private func route(
        hasConfig: Bool = true,
        restoring: Bool = false,
        uid: String? = "uid-1",
        user: AppUser? = nil,
        deviceAuthEnabled: Bool = false,
        deviceAuthVerified: Bool = false
    ) -> AppRoute {
        AppRoute.determine(
            hasFirebaseConfig: hasConfig,
            isRestoring: restoring,
            uid: uid,
            user: user,
            deviceAuthEnabled: deviceAuthEnabled,
            deviceAuthVerified: deviceAuthVerified
        )
    }

    private let completeProfile: [String: Any] = [
        "dob": "1990-01-01", "address": "1 Test St", "phone": "0400000000",
    ]
    private var staff: AppUser { TestSupport.user(extra: completeProfile) }
    private var manager: AppUser { TestSupport.user(role: "manager") }

    // MARK: - Pre-auth states

    func testMissingConfigWinsOverEverything() {
        XCTAssertEqual(route(hasConfig: false, uid: "u", user: staff), .setup)
    }

    func testRestoring() {
        XCTAssertEqual(route(restoring: true), .restoring)
    }

    func testNoSessionShowsLogin() {
        XCTAssertEqual(route(uid: nil), .login)
    }

    func testSessionWithoutProfileShowsLoading() {
        XCTAssertEqual(route(user: nil), .profileLoading)
    }

    // MARK: - Happy paths

    func testStaffMain() {
        XCTAssertEqual(route(user: staff), .staffMain)
    }

    func testManagerMain() {
        XCTAssertEqual(route(user: manager), .managerMain)
    }

    // MARK: - Forced password change (both roles)

    func testStaffForcedPasswordChange() {
        let user = TestSupport.user(extra: completeProfile.merging(["mustChangePassword": true]) { _, n in n })
        XCTAssertEqual(route(user: user), .forcedPasswordChange)
    }

    func testManagerForcedPasswordChange_milestone3Fix() {
        let user = TestSupport.user(role: "manager", extra: ["mustChangePassword": true])
        XCTAssertEqual(route(user: user), .forcedPasswordChange,
                       "managers must not bypass the forced password change gate")
    }

    // MARK: - Profile completion (staff only, by model)

    func testStaffIncompleteProfileGated() {
        XCTAssertEqual(route(user: TestSupport.user()), .profileCompletion)
    }

    func testStaffProfileUpdateRequiredGated() {
        let user = TestSupport.user(extra: completeProfile.merging(["profileUpdateRequired": true]) { _, n in n })
        XCTAssertEqual(route(user: user), .profileCompletion)
    }

    func testManagerNeverGatedOnProfile() {
        XCTAssertEqual(route(user: TestSupport.user(role: "manager")), .managerMain,
                       "needsProfileCompletion is false for managers by model")
    }

    // MARK: - Device auth gate (both roles)

    func testStaffDeviceAuthGate() {
        XCTAssertEqual(route(user: staff, deviceAuthEnabled: true, deviceAuthVerified: false), .deviceAuthGate)
        XCTAssertEqual(route(user: staff, deviceAuthEnabled: true, deviceAuthVerified: true), .staffMain)
    }

    func testManagerDeviceAuthGate_milestone3Fix() {
        XCTAssertEqual(route(user: manager, deviceAuthEnabled: true, deviceAuthVerified: false), .deviceAuthGate,
                       "managers must not bypass the biometric lock")
        XCTAssertEqual(route(user: manager, deviceAuthEnabled: true, deviceAuthVerified: true), .managerMain)
    }

    // MARK: - Gate precedence

    func testPasswordChangeBeatsProfileCompletionAndDeviceAuth() {
        let user = TestSupport.user(extra: ["mustChangePassword": true]) // also incomplete profile
        XCTAssertEqual(route(user: user, deviceAuthEnabled: true), .forcedPasswordChange)
    }

    func testProfileCompletionBeatsDeviceAuth() {
        XCTAssertEqual(route(user: TestSupport.user(), deviceAuthEnabled: true), .profileCompletion)
    }
}
