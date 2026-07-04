import SwiftUI

/// A reusable week navigator + 7-day strip, shared by Roster and Availability.
/// Optimised for one-handed use: large tap targets, prev/next arrows near the
/// edges, and a "Today" quick-jump.
struct WeekSelector: View {
    let monday: Date
    @Binding var selectedKey: String
    var markedKeys: Set<String> = []
    var lockedKeys: Set<String> = []
    var canGoPrev: Bool = true
    var canGoNext: Bool = true
    var onPrev: () -> Void
    var onNext: () -> Void
    var onToday: () -> Void
    var onSelect: (String) -> Void

    private var days: [Date] { RosterCalendar.weekDays(for: monday) }
    private var todayKey: String { RosterCalendar.todayKey() }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                navButton(system: "chevron.left", enabled: canGoPrev, action: onPrev)
                Spacer()
                VStack(spacing: 2) {
                    Text(RosterFormat.weekRange(monday: monday))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Button(action: onToday) {
                        Text("Today")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                    }
                }
                Spacer()
                navButton(system: "chevron.right", enabled: canGoNext, action: onNext)
            }

            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    dayChip(day)
                }
            }
        }
    }

    private func navButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: system)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? Theme.brand : Theme.textTertiary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.brand.opacity(enabled ? 0.10 : 0.04)))
        }
        .disabled(!enabled)
        .accessibilityLabel(system == "chevron.left" ? "Previous week" : "Next week")
    }

    private func dayChip(_ day: Date) -> some View {
        let key = RosterCalendar.dayFormatter.string(from: day)
        let isSelected = key == selectedKey
        let isToday = key == todayKey
        let isMarked = markedKeys.contains(key)
        let isLocked = lockedKeys.contains(key)
        let weekdayLabel = shortWeekday(day)
        let dayNumber = dayNumber(day)

        return Button {
            Haptics.selection()
            onSelect(key)
        } label: {
            VStack(spacing: 5) {
                Text(weekdayLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Theme.textTertiary)
                Text(dayNumber)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
                Circle()
                    .fill(isMarked ? (isSelected ? Color.white : Theme.brand) : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.brand : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isToday && !isSelected ? Theme.brand.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
            .opacity(isLocked ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(RosterFormat.weekdayLong(key)) \(dayNumber)\(isMarked ? ", has shift" : "")\(isLocked ? ", locked" : "")")
    }

    private func shortWeekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = RosterCalendar.timeZone
        f.dateFormat = "EEEEE" // single letter
        return f.string(from: date)
    }

    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = RosterCalendar.timeZone
        f.dateFormat = "d"
        return f.string(from: date)
    }
}
