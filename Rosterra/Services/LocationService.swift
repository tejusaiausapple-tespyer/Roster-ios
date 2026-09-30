import Foundation
import CoreLocation

/// One-shot GPS capture for shift start/end verification.
///
/// Requests when-in-use permission on first use and returns a single fresh fix.
/// Failures are reported as typed errors so the clock-in flow can distinguish
/// "user denied location" (record as unverified) from "no fix yet" (retryable).
@MainActor
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
    // All callers share one permission/fix request, but retain their own
    // continuation so cancelling one caller cannot strand or cancel another.
    private var waiters: [UUID: CheckedContinuation<CLLocation, Error>] = [:]
    private var requestingFix = false
    private var requestTimeout: Task<Void, Never>?


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

    /// Concurrent callers share a GPS request. Every caller completes exactly
    /// once on success, denial, timeout, or cancellation.
    func currentLocation() async throws -> CLLocation {
        try Task.checkCancellation()
        let status = manager.authorizationStatus
        guard status != .denied && status != .restricted else {
            throw LocationError.denied
        }
        if let cached = manager.location, cached.timestamp > Date(timeIntervalSinceNow: -30),
           cached.horizontalAccuracy >= 0 {
            return cached
        }

        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                // Covers cancellation that occurred before the handler's
                // MainActor cleanup could run or before registration.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let startsRequest = waiters.isEmpty
                waiters[id] = continuation
                guard startsRequest else { return }
                requestTimeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                    catch { return }
                    self?.finish(.failure(LocationError.unavailable))
                }
                if manager.authorizationStatus == .notDetermined {
                    manager.requestWhenInUseAuthorization()
                } else {
                    requestFixIfNeeded()
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let waiter = self.waiters.removeValue(forKey: id) else { return }
                if self.waiters.isEmpty { self.stopRequest() }
                waiter.resume(throwing: CancellationError())
            }
        })
    }

    private func requestFixIfNeeded() {
        guard !waiters.isEmpty, !requestingFix else { return }
        requestingFix = true
        manager.requestLocation()
    }

    private func stopRequest() {
        requestTimeout?.cancel()
        requestTimeout = nil
        requestingFix = false
        manager.stopUpdatingLocation()
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let continuations = Array(waiters.values)
        waiters.removeAll()
        stopRequest()
        continuations.forEach { $0.resume(with: result) }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.requestFixIfNeeded()
            case .denied, .restricted:
                self.finish(.failure(LocationError.denied))
            case .notDetermined:
                break
            @unknown default:
                self.finish(.failure(LocationError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last(where: {
            $0.horizontalAccuracy >= 0 && $0.timestamp > Date(timeIntervalSinceNow: -30)
        })
        Task { @MainActor [weak self] in
            guard let self, self.requestingFix else { return }
            if let location {
                self.finish(.success(location))
            } else {
                self.finish(.failure(LocationError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            guard let self, self.requestingFix else { return }
            self.finish(.failure(denied ? LocationError.denied : LocationError.unavailable))
        }
    }
}
