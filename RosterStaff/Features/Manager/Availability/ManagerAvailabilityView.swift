import SwiftUI

// Manager view of every staff member's weekly availability, to spot coverage
// gaps. Week selector + matrix (wide) / per-staff cards (narrow). Read-only.
struct ManagerAvailabilityView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var weekOffset = 0

    private var now: Date { Date() }
    private var bounds: (min: Int, max: Int) {
        (BusinessRules.availabilityMinWeekOffset, BusinessRules.availabilityMaxWeekOffset)
    }
    private var monday: Date { RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart(now)) }
    private var weekKey: String { RosterCalendar.weekStartKey(monday) }

    private var dateRangeString: String {
        let days = RosterCalendar.weekDays(for: monday)
        guard let first = days.first, let last = days.last else { return "" }
        let f = DateFormatter(); f.calendar = RosterCalendar.calendar; f.timeZone = RosterCalendar.timeZone; f.dateFormat = "d MMM"
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }

    private var weekRelativeLabel: String {
        switch weekOffset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        case let n where n > 1: return "In \(n) weeks"
        default: return "\(-weekOffset) weeks ago"
        }
    }

    private var staff: [AppUser] {
        repo.allUsers.filter { $0.role == .staff }.sorted { $0.fullName < $1.fullName }
    }

    private func availability(for user: AppUser) -> UserAvailability {
        user.weeklyAvailability[weekKey] ?? user.availability ?? .defaultAvailability
    }

    /// How many staff are available on a given weekday this week.
    private func availableCount(_ day: Weekday) -> Int {
        staff.filter { availability(for: $0)[day].available }.count
    }

    private func layoutIsWide(_ width: CGFloat) -> Bool {
        UIDevice.current.userInterfaceIdiom != .phone && width >= 720
    }

    var embedInNavigationStack = true

    var body: some View {
        if embedInNavigationStack {
            NavigationStack { rootContent }
        } else {
            rootContent
        }
    }

    private var rootContent: some View {
        GeometryReader { proxy in
            let wide = layoutIsWide(proxy.size.width)
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    controlBar
                    content(wide: wide, width: proxy.size.width)
                    summaryBar
                }
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Availability")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Availability", icon: "calendar.badge.clock")
            }
        }
        // GeometryReader evaluates its closure during layout, outside @Observable tracking.
        // This anchors repo.allUsers as a dependency so the view re-renders when staff save.
        .onChange(of: repo.allUsers) { _, _ in }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            weekNavCluster
            Text(dateRangeString)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var weekNavCluster: some View {
        HStack(spacing: 2) {
            navArrow("chevron.left", enabled: weekOffset > bounds.min) {
                if weekOffset > bounds.min { weekOffset -= 1 }
            }
            Button {
                weekOffset = 0
            } label: {
                HStack(spacing: 6) {
                    Text(weekRelativeLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(weekOffset == 0 ? Theme.textPrimary : Theme.brand)
                    if weekOffset != 0 {
                        Image(systemName: "arrow.uturn.backward").font(.caption2.weight(.bold)).foregroundStyle(Theme.brand)
                    }
                }
                .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(weekOffset == 0)
            navArrow("chevron.right", enabled: weekOffset < bounds.max) {
                if weekOffset < bounds.max { weekOffset += 1 }
            }
        }
        .padding(.horizontal, 4)
        .glassCapsule()
    }

    private func navArrow(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.footnote.weight(.bold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(wide: Bool, width: CGFloat) -> some View {
        if staff.isEmpty {
            emptyState
        } else if wide {
            matrix(width: width)
        } else {
            narrowList
        }
    }

    // Wide: staff × 7-day matrix
    private func matrix(width: CGFloat) -> some View {
        let hPad: CGFloat = 16
        let nameCol: CGFloat = 150
        let spacing: CGFloat = 6
        let cellW = max(48, (min(width, Theme.maxContentWidth) - hPad * 2 - nameCol - spacing * 7) / 7)

        return ScrollView {
            VStack(spacing: 6) {
                // Header
                HStack(spacing: spacing) {
                    Text("STAFF")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: nameCol, alignment: .leading)
                    ForEach(Weekday.allCases) { day in
                        VStack(spacing: 1) {
                            Text(day.shortLabel).font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                            Text("\(availableCount(day))").font(.caption2.weight(.bold)).foregroundStyle(Theme.brand)
                        }
                        .frame(width: cellW)
                    }
                }
                Divider().overlay(Theme.separator)

                ForEach(staff) { user in
                    let avail = availability(for: user)
                    HStack(spacing: spacing) {
                        HStack(spacing: 8) {
                            Text(user.initials)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.brand)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Theme.brand.opacity(0.12)))
                            Text(user.fullName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(width: nameCol, alignment: .leading)

                        ForEach(Weekday.allCases) { day in
                            dayCell(avail[day]).frame(width: cellW)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider().overlay(Theme.separator.opacity(0.5))
                }
            }
            .padding(hPad)
        }
    }

    // Narrow: per-staff cards
    private var narrowList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(staff) { user in
                    let avail = availability(for: user)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(user.initials)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.brand)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Theme.brand.opacity(0.12)))
                            Text(user.fullName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        HStack(spacing: 4) {
                            ForEach(Weekday.allCases) { day in
                                VStack(spacing: 3) {
                                    Text(String(day.shortLabel.prefix(1)))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Theme.textTertiary)
                                    dayCell(avail[day], compact: true)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                }
            }
            .padding(16)
        }
    }

    private func dayCell(_ day: DayAvailability, compact: Bool = false) -> some View {
        let (label, tint): (String, Color) = {
            if !day.available { return ("Off", Theme.error) }
            if day.allDay { return ("All day", Theme.accent) }
            let s = day.start ?? "—"; let e = day.end ?? "—"
            return ("\(s)–\(e)", Theme.accent)
        }()
        return Text(label)
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: compact ? 30 : 34)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.12)))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No staff to show")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Summary footer

    private var summaryBar: some View {
        let busiest = Weekday.allCases.max(by: { availableCount($0) < availableCount($1) })
        let content = HStack(spacing: 16) {
            summaryChip(icon: "person.2", text: "\(staff.count) staff")
            if let busiest {
                summaryChip(icon: "chart.bar.fill", text: "Best cover: \(busiest.shortLabel) (\(availableCount(busiest)))")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)

        return ViewThatFits(in: .horizontal) {
            content
            ScrollView(.horizontal, showsIndicators: false) { content }
        }
        .glassCapsule()
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func summaryChip(icon: String, text: String, tint: Color = Theme.textPrimary) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }
}

#Preview {
    ManagerAvailabilityView()
        .environment(RosterRepository())
}
