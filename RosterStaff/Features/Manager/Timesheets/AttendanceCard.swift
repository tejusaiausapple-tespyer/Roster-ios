import SwiftUI

/// Manager-portal card showing the verified attendance record for a shift:
/// server-recorded clock-in/out times, GPS verdicts, and a device-clock
/// tamper indicator. Times here come from `FieldValue.serverTimestamp()`,
/// not the staff member's device clock.
struct AttendanceCard: View {
    let attendance: ShiftAttendance
    /// The rostered shift, for early check-in context. Optional — the record
    /// stands alone if the shift was deleted.
    var shift: Shift? = nil

    /// Device-vs-server gaps beyond this are flagged as suspicious.
    private static let skewThreshold: TimeInterval = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.brand)
                Text("VERIFIED ATTENDANCE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }

            Divider().overlay(Theme.separator)

            eventRow(title: "Clock in", at: attendance.clockInAt,
                     fix: attendance.clockInFix, skew: attendance.clockInSkewSeconds)

            // Early check-in: show both instants and where paid time begins.
            if let shift, let clockIn = attendance.clockInAt, clockIn < shift.startDateTime {
                let early = Int(shift.startDateTime.timeIntervalSince(clockIn) / 60)
                Label("Checked in \(max(1, early)) min before the rostered start (\(RosterFormat.time(shift.rosteredStart))). Paid time begins at the rostered start.",
                      systemImage: "clock.badge.checkmark")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }

            if attendance.clockOutAt != nil || attendance.clockOutFix != nil {
                Divider().overlay(Theme.separator)
                eventRow(title: "Clock out", at: attendance.clockOutAt,
                         fix: attendance.clockOutFix, skew: attendance.clockOutSkewSeconds)

                // Early-leave context: how much earlier, and the staff note.
                if let shift, let out = attendance.clockOutAt, out < shift.endDateTime {
                    let early = Int(shift.endDateTime.timeIntervalSince(out) / 60)
                    Label("Left \(max(1, early)) min before the rostered end (\(RosterFormat.time(shift.rosteredEnd)))",
                          systemImage: "figure.walk.departure")
                        .font(.caption2)
                        .foregroundStyle(Theme.warning)
                }
                if let note = attendance.clockOutNote, !note.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "text.bubble")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                        Text("“\(note)”")
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.background))
                }
            } else {
                Divider().overlay(Theme.separator)
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                    Text("Still on the clock — no clock-out recorded yet.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).strokeBorder(Theme.separator, lineWidth: 1))
    }

    private func eventRow(title: String, at: Date?, fix: ShiftAttendance.Fix?, skew: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let fix {
                    geofencePill(fix)
                }
            }

            if let at {
                Text(RosterFormat.dateTime(at))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("Not recorded")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }

            if let fix {
                HStack(spacing: 10) {
                    if let distance = fix.distanceFromWorkplace {
                        Label(Self.distance(distance) + " from workplace", systemImage: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Link(destination: mapURL(fix)) {
                        Label("View on map", systemImage: "map")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                    }
                }
            } else {
                Label("No GPS fix recorded", systemImage: "location.slash")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            if let skew, abs(skew) > Self.skewThreshold {
                Label("Device clock was \(Self.duration(abs(skew))) \(skew > 0 ? "ahead of" : "behind") server time",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private func geofencePill(_ fix: ShiftAttendance.Fix) -> some View {
        let (tint, icon): (Color, String) = switch fix.geofence {
        case .inside: (Theme.accent, "checkmark.circle.fill")
        case .outside: (Theme.warning, "exclamationmark.triangle.fill")
        case .unknown: (Theme.textTertiary, "questionmark.circle")
        }
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(fix.geofence.label)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func mapURL(_ fix: ShiftAttendance.Fix) -> URL {
        URL(string: "https://maps.apple.com/?ll=\(fix.latitude),\(fix.longitude)&q=Shift+attendance")!
    }

    private static func distance(_ metres: Double) -> String {
        metres >= 1000
            ? String(format: "%.1f km", metres / 1000)
            : "\(Int(metres.rounded())) m"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        seconds >= 3600
            ? String(format: "%.1f h", seconds / 3600)
            : "\(Int(seconds / 60)) min"
    }
}
