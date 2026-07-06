import Foundation
import CoreLocation
import FirebaseFirestore

/// Verified clock-in/out record for one shift, stored in `shift_attendance/{shiftId}`.
///
/// Unlike the device-local ClockSession (which drives the live timer UI), this
/// document is the tamper-resistant record managers see:
/// - `clockInAt` / `clockOutAt` are written with `FieldValue.serverTimestamp()`,
///   so changing the phone's clock cannot forge them.
/// - `clockInDeviceAt` / `clockOutDeviceAt` keep the device's own clock at the
///   same moment; a large gap between the two exposes clock manipulation.
/// - GPS fixes are captured at both taps, with a geofence verdict against the
///   shift's saved workplace location.
struct ShiftAttendance: Identifiable, Equatable {
    enum GeofenceStatus: String {
        case inside      // within the workplace radius
        case outside     // confirmed outside the radius
        case unknown     // no workplace coordinates / no GPS fix

        var label: String {
            switch self {
            case .inside: return "At workplace"
            case .outside: return "Outside workplace"
            // Shown when a fix exists but the shift's location has no
            // geofence coordinates saved, so no distance check was possible.
            case .unknown: return "No geofence set"
            }
        }
    }

    /// One captured GPS fix.
    struct Fix: Equatable {
        var latitude: Double
        var longitude: Double
        var accuracy: Double            // horizontal accuracy in metres
        var geofence: GeofenceStatus
        var distanceFromWorkplace: Double?  // metres, when workplace coords exist

        init(latitude: Double, longitude: Double, accuracy: Double,
             geofence: GeofenceStatus, distanceFromWorkplace: Double?) {
            self.latitude = latitude
            self.longitude = longitude
            self.accuracy = accuracy
            self.geofence = geofence
            self.distanceFromWorkplace = distanceFromWorkplace
        }

        /// Evaluate a GPS fix against the shift's saved workplace geofence.
        /// The fix's accuracy is added to the allowed radius so staff with a
        /// weak signal at the right place aren't flagged as outside.
        /// `allowedRadius` overrides the workplace's configured radius (used
        /// for the lenient 250 m allowance when enforcement is off).
        init(location: CLLocation, workplace: RosterLocation?, allowedRadius: Double? = nil) {
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            accuracy = max(0, location.horizontalAccuracy)
            if let workplace, let lat = workplace.latitude, let lon = workplace.longitude {
                let distance = location.distance(from: CLLocation(latitude: lat, longitude: lon))
                distanceFromWorkplace = distance
                let allowed = (allowedRadius ?? workplace.effectiveGeofenceRadius) + accuracy
                geofence = distance <= allowed ? .inside : .outside
            } else {
                distanceFromWorkplace = nil
                geofence = .unknown
            }
        }
    }

    let id: String          // == shiftId
    var shiftId: String
    var staffId: String
    var date: String        // YYYY-MM-DD (manager window queries)
    var location: String?   // shift's location string at clock-in

    var clockInAt: Date?            // server time (authoritative)
    var clockInDeviceAt: Date?      // device clock at the same moment
    var clockInFix: Fix?

    var clockOutAt: Date?
    var clockOutDeviceAt: Date?
    var clockOutFix: Fix?
    /// Staff-supplied reason when ending before the rostered end (unwell,
    /// family emergency, …). Shown to managers alongside the clock-out.
    var clockOutNote: String?

    /// Device-vs-server clock gap at clock-in, in seconds (positive = device ahead).
    var clockInSkewSeconds: TimeInterval? {
        guard let clockInAt, let clockInDeviceAt else { return nil }
        return clockInDeviceAt.timeIntervalSince(clockInAt)
    }

    var clockOutSkewSeconds: TimeInterval? {
        guard let clockOutAt, let clockOutDeviceAt else { return nil }
        return clockOutDeviceAt.timeIntervalSince(clockOutAt)
    }

    // MARK: - Firestore mapping

    init?(id: String, data: [String: Any]) {
        let staffId = FS.stringValue(data, "staffId")
        guard !staffId.isEmpty else { return nil }
        self.id = id
        self.shiftId = FS.stringValue(data, "shiftId", default: id)
        self.staffId = staffId
        self.date = FS.stringValue(data, "date")
        self.location = FS.string(data, "location")
        self.clockInAt = FS.date(data, "clockInAt")
        self.clockInDeviceAt = FS.date(data, "clockInDeviceAt")
        self.clockInFix = Self.fix(from: data, prefix: "clockIn")
        self.clockOutAt = FS.date(data, "clockOutAt")
        self.clockOutDeviceAt = FS.date(data, "clockOutDeviceAt")
        self.clockOutFix = Self.fix(from: data, prefix: "clockOut")
        self.clockOutNote = FS.string(data, "clockOutNote")
    }

    private static func fix(from data: [String: Any], prefix: String) -> Fix? {
        guard let point = data["\(prefix)Location"] as? GeoPoint else { return nil }
        let distance = data["\(prefix)DistanceM"] as? NSNumber
        return Fix(
            latitude: point.latitude,
            longitude: point.longitude,
            accuracy: FS.double(data, "\(prefix)AccuracyM"),
            geofence: GeofenceStatus(rawValue: FS.stringValue(data, "\(prefix)Geofence", default: "unknown")) ?? .unknown,
            distanceFromWorkplace: distance?.doubleValue
        )
    }

    /// Field payload for one clock event (start or end). Server timestamp is
    /// injected by the caller with `FieldValue.serverTimestamp()`.
    static func fixFields(prefix: String, fix: Fix?) -> [String: Any] {
        var fields: [String: Any] = [:]
        if let fix {
            fields["\(prefix)Location"] = GeoPoint(latitude: fix.latitude, longitude: fix.longitude)
            fields["\(prefix)AccuracyM"] = fix.accuracy
            fields["\(prefix)Geofence"] = fix.geofence.rawValue
            if let distance = fix.distanceFromWorkplace {
                fields["\(prefix)DistanceM"] = distance
            }
        } else {
            fields["\(prefix)Geofence"] = GeofenceStatus.unknown.rawValue
        }
        return fields
    }
}
