import Foundation
import CoreLocation

/// One-shot GPS capture for shift start/end verification.
///
/// Requests when-in-use permission on first use and returns a single fresh fix.
/// Failures are reported as typed errors so the clock-in flow can distinguish
/// "user denied location" (record as unverified) from "no fix yet" (retryable).
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Location access is off. Enable it in Settings so your shift location can be verified."
            case .unavailable:
                return "Couldn't get a GPS fix. Move to an open area and try again."
            }
        }
    }

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var fixContinuation: CheckedContinuation<CLLocation, Error>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Show the when-in-use permission prompt if it hasn't been decided yet,
    /// without waiting for a fix. Called when a staff session opens so the
    /// prompt appears during onboarding rather than mid-clock-in.
    @MainActor
    func primePermission() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Current fix, requesting permission first if needed. Runs on the main
    /// actor because CLLocationManager delivers callbacks on the thread that
    /// created it and the callers are all UI-driven.
    @MainActor
    func currentLocation() async throws -> CLLocation {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw LocationError.denied
        }

        // A recent cached fix (<30s) is fine for attendance and avoids the
        // multi-second cold-start wait.
        if let cached = manager.location, cached.timestamp > Date(timeIntervalSinceNow: -30),
           cached.horizontalAccuracy >= 0 {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined, let continuation = authContinuation {
            authContinuation = nil
            continuation.resume(returning: manager.authorizationStatus)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = fixContinuation else { return }
        fixContinuation = nil
        if let location = locations.last {
            continuation.resume(returning: location)
        } else {
            continuation.resume(throwing: LocationError.unavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = fixContinuation else { return }
        fixContinuation = nil
        if let clError = error as? CLError, clError.code == .denied {
            continuation.resume(throwing: LocationError.denied)
        } else {
            continuation.resume(throwing: LocationError.unavailable)
        }
    }
}
