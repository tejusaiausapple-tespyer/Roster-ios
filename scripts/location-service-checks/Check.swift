import Foundation
import CoreLocation
@main struct Check {
 @MainActor static func settle() async { try? await Task.sleep(nanoseconds: 20_000_000) }
 @MainActor static func main() async throws {
  let service = LocationService.shared
  let manager = CLLocationManager.last!
  let a = Task { try await service.currentLocation() }
  let b = Task { try await service.currentLocation() }
  await settle()
  precondition(manager.fixRequests == 1)
  let fix = CLLocation()
  service.locationManager(manager, didUpdateLocations: [fix])
  let av = try await a.value; let bv = try await b.value
  precondition(av === fix && bv === fix)
  print("PASS concurrent callers share one request and both resume")
  let c = Task { try await service.currentLocation() }
  let d = Task { try await service.currentLocation() }
  await settle(); c.cancel(); await settle()
  if case .failure(let error) = await c.result { precondition(error is CancellationError) } else { fatalError("cancel failed") }
  service.locationManager(manager, didUpdateLocations: [fix])
  _ = try await d.value
  print("PASS cancelling one caller preserves the other")
  manager.authorizationStatus = .notDetermined
  let e = Task { try await service.currentLocation() }
  let f = Task { try await service.currentLocation() }
  await settle(); precondition(manager.authRequests == 1)
  let before = manager.fixRequests
  manager.authorizationStatus = .authorizedWhenInUse
  service.locationManagerDidChangeAuthorization(manager)
  await settle(); precondition(manager.fixRequests == before + 1)
  service.locationManager(manager, didFailWithError: CLError(.locationUnknown))
  if case .failure = await e.result {} else { fatalError("error missing") }
  if case .failure = await f.result {} else { fatalError("error missing") }
  print("PASS shared permission request and both fail on GPS error")
  manager.authorizationStatus = .notDetermined
  let g = Task { try await service.currentLocation() }
  let h = Task { try await service.currentLocation() }
  await settle(); manager.authorizationStatus = .denied
  service.locationManagerDidChangeAuthorization(manager)
  if case .failure(let error) = await g.result { precondition(error as? LocationService.LocationError == .denied) } else { fatalError("denial missing") }
  if case .failure(let error) = await h.result { precondition(error as? LocationService.LocationError == .denied) } else { fatalError("denial missing") }
  print("PASS permission denial completes every waiter")
  manager.authorizationStatus = .authorizedWhenInUse
  let i = Task { try await service.currentLocation() }
  await settle(); i.cancel(); _ = await i.result
  let j = Task { try await service.currentLocation() }
  await settle(); service.locationManager(manager, didUpdateLocations: [fix]); _ = try await j.value
  print("PASS last-caller cancellation permits a fresh request")
  let k = Task { try await service.currentLocation() }
  await settle(); service.locationManager(manager, didUpdateLocations: [CLLocation(timestamp: Date(timeIntervalSinceNow: -60))])
  if case .failure(let error) = await k.result { precondition(error as? LocationService.LocationError == .unavailable) } else { fatalError("stale fix accepted") }
  print("PASS stale location rejected")
 }
}
