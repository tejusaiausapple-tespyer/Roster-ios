import XCTest
@testable import Rosterra

/// Covers the two pieces of `AuthViewModel`'s state machine that are safe to
/// exercise directly in a fast, hermetic unit test — the gate-skip decision
/// in `handleAuthState` and the background-relock timer in
/// `handleScenePhase`. `login()` itself isn't covered here: it calls live
/// Firebase Auth + Firestore with no injected seam, so a real test would
/// either need a Firebase emulator harness or a dependency-injection
/// refactor of the class — out of scope for this pass.
@MainActor
final class AuthViewModelTests: XCTestCase {

    // MARK: - handleAuthState: fresh login vs restored session

    /// Signing out (uid: nil) always clears both device-auth flags,
    /// regardless of their prior state.
    func testSignOutClearsDeviceAuthFlags() {
        let vm = AuthViewModel()
        vm.deviceAuthEnabled = true
        vm.deviceAuthVerified = true

        vm.handleAuthState(uid: nil)

        XCTAssertNil(vm.uid)
        XCTAssertFalse(vm.isRestoring)
        XCTAssertFalse(vm.deviceAuthEnabled)
        XCTAssertFalse(vm.deviceAuthVerified)
    }

    /// A fresh, genuine credential login (isLoggingIn true, set by `login()`
    /// for its duration) must skip the device-auth gate even if the account
    /// has one enabled — the whole point of `isLoggingIn` existing.
    func testFreshLoginSkipsDeviceAuthGate() {
        let vm = AuthViewModel()
        vm.isLoggingIn = true
        vm.deviceAuthVerified = false

        vm.handleAuthState(uid: "staff-1")

        XCTAssertEqual(vm.uid, "staff-1")
        XCTAssertTrue(vm.deviceAuthVerified, "a fresh login must not be re-gated")
    }

    /// A restored session (app relaunch, isLoggingIn false) with the gate
    /// enabled must re-require it — this is the exact distinction a past
    /// bug lived in (restored sessions incorrectly skipping the gate).
    ///
    /// `handleAuthState` derives `deviceAuthEnabled` itself from
    /// `DeviceAuthService.shared.isEnabled(uid:)` (a real Keychain read) —
    /// presetting `vm.deviceAuthEnabled` before the call has no effect, it
    /// gets overwritten. So this test seeds the same Keychain key
    /// `DeviceAuthService` uses directly (not via its `enable(uid:)`, which
    /// would trigger a real biometric/passcode prompt — unusable in a unit
    /// test) and cleans it up afterward.
    func testRestoredSessionWithGateEnabledRequiresVerification() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Unsigned Mac Catalyst test hosts cannot persist the Keychain seed used by this test.")
        #else
        let uid = "test-uid-\(UUID().uuidString)"
        let keychainKey = "roster_device_auth_\(uid)"
        KeychainHelper.set("2026-01-01T00:00:00Z", for: keychainKey)
        defer { KeychainHelper.delete(keychainKey) }

        let vm = AuthViewModel()
        vm.isLoggingIn = false
        vm.deviceAuthVerified = false

        vm.handleAuthState(uid: uid)

        XCTAssertTrue(vm.deviceAuthEnabled, "precondition: seeded Keychain entry should read as enabled")
        XCTAssertFalse(vm.deviceAuthVerified, "a restored session must still pass the gate")
        #endif
    }

    /// A restored session already marked verified this run (e.g. a second
    /// snapshot delivery for the same listener) must not be flipped back —
    /// only an *unverified* restored session re-gates.
    func testRestoredSessionAlreadyVerifiedStaysVerified() {
        let vm = AuthViewModel()
        vm.isLoggingIn = false
        vm.deviceAuthVerified = true

        vm.handleAuthState(uid: "staff-1")

        XCTAssertTrue(vm.deviceAuthVerified)
    }

    // MARK: - handleScenePhase: background relock timer

    func testBackgroundingClearsTemporaryPassword() {
        let vm = AuthViewModel()
        vm.temporaryPassword = "hunter2"

        vm.handleScenePhase(.background, now: Date())

        XCTAssertNil(vm.temporaryPassword)
    }

    /// Returning to foreground before the relock threshold elapses must not
    /// re-lock a device-auth-enabled session.
    func testForegroundBeforeThresholdKeepsSessionUnlocked() {
        let vm = AuthViewModel()
        vm.deviceAuthEnabled = true
        vm.deviceAuthVerified = true
        let t0 = Date()

        vm.handleScenePhase(.background, now: t0)
        vm.handleScenePhase(.active, now: t0.addingTimeInterval(AppConfig.deviceAuthBackgroundRelock - 1))

        XCTAssertTrue(vm.deviceAuthVerified)
    }

    /// Returning to foreground at/after the relock threshold must re-lock a
    /// device-auth-enabled session.
    func testForegroundAtThresholdRelocksSession() {
        let vm = AuthViewModel()
        vm.deviceAuthEnabled = true
        vm.deviceAuthVerified = true
        let t0 = Date()

        vm.handleScenePhase(.background, now: t0)
        vm.handleScenePhase(.active, now: t0.addingTimeInterval(AppConfig.deviceAuthBackgroundRelock))

        XCTAssertFalse(vm.deviceAuthVerified)
    }

    /// No device-auth gate configured at all — elapsed time is irrelevant,
    /// nothing to relock.
    func testForegroundAfterThresholdWithGateDisabledStaysUnlocked() {
        let vm = AuthViewModel()
        vm.deviceAuthEnabled = false
        vm.deviceAuthVerified = true
        let t0 = Date()

        vm.handleScenePhase(.background, now: t0)
        vm.handleScenePhase(.active, now: t0.addingTimeInterval(AppConfig.deviceAuthBackgroundRelock + 60))

        XCTAssertTrue(vm.deviceAuthVerified)
    }

    /// Never backgrounded this session (no prior `.background` call) —
    /// `.active` must be a no-op on the verified flag.
    func testActiveWithNoPriorBackgroundDoesNotRelock() {
        let vm = AuthViewModel()
        vm.deviceAuthEnabled = true
        vm.deviceAuthVerified = true

        vm.handleScenePhase(.active, now: Date())

        XCTAssertTrue(vm.deviceAuthVerified)
    }

    // MARK: - forceSignOut: synchronous message state

    /// `forcedSignOutMessage` is set synchronously, before the async
    /// sign-out work even starts — LoginView reads it immediately to show
    /// why the user landed back there.
    func testForceSignOutSetsMessageSynchronously() {
        let vm = AuthViewModel()

        vm.forceSignOut(message: "Your account was locked.")

        XCTAssertEqual(vm.forcedSignOutMessage, "Your account was locked.")
    }
}
