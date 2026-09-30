import Foundation
public let kCLLocationAccuracyNearestTenMeters = 10.0
public enum CLAuthorizationStatus { case notDetermined, restricted, denied, authorizedAlways, authorizedWhenInUse }
public struct CLError: Error { public enum Code { case denied, locationUnknown }; public let code: Code; public init(_ code: Code) { self.code = code } }
public class CLLocation { public let timestamp: Date; public let horizontalAccuracy: Double; public init(timestamp: Date = Date(), accuracy: Double = 10) { self.timestamp = timestamp; horizontalAccuracy = accuracy } }
public protocol CLLocationManagerDelegate: AnyObject {
 func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
 func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
 func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
}
public class CLLocationManager {
 public static var last: CLLocationManager!
 public var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
 public weak var delegate: CLLocationManagerDelegate?
 public var desiredAccuracy = 0.0
 public var location: CLLocation?
 public var fixRequests = 0
 public var authRequests = 0
 public init() { Self.last = self }
 public func requestLocation() { fixRequests += 1 }
 public func requestWhenInUseAuthorization() { authRequests += 1 }
 public func stopUpdatingLocation() {}
}
