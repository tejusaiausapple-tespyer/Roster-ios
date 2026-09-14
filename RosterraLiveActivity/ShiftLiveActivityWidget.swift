import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct RosterraLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        ShiftLiveActivityWidget()
    }
}

struct ShiftLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftLiveActivityAttributes.self) { context in
            ShiftLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.07, green: 0.09, blue: 0.16))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(ShiftLiveActivityLinks.home(shiftID: context.attributes.shiftID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(spacing: 1) {
                        Text("\(context.state.completedJobs)/\(context.state.totalJobs)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                        Text("Jobs done")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(brand)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Jobs, \(context.state.completedJobs) of \(context.state.totalJobs) complete"
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.companyName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    liveTimer(context)
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shiftTime(context.attributes))
                                .font(.subheadline.weight(.semibold))
                            if !context.attributes.location.isEmpty {
                                Text(context.attributes.location)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        actionLink(context)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Text("\(context.state.completedJobs)/\(context.state.totalJobs)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(brand)
                    .accessibilityLabel(
                        "\(context.state.completedJobs) of \(context.state.totalJobs) jobs complete"
                    )
            } compactTrailing: {
                liveTimer(context)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundStyle(statusColor(context.state.phase))
            }
            .widgetURL(ShiftLiveActivityLinks.home(shiftID: context.attributes.shiftID))
            .keylineTint(brand)
        }
    }

    private let brand = Color(red: 0.31, green: 0.27, blue: 0.90)

    private func phaseIcon(_ phase: ShiftLiveActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .ready: return "play.fill"
        case .working: return "briefcase.fill"
        case .onBreak: return "cup.and.saucer.fill"
        }
    }

    private func statusColor(_ phase: ShiftLiveActivityAttributes.ContentState.Phase) -> Color {
        switch phase {
        case .ready: return brand
        case .working: return .green
        case .onBreak: return .orange
        }
    }

    @ViewBuilder
    private func liveTimer(
        _ context: ActivityViewContext<ShiftLiveActivityAttributes>
    ) -> some View {
        if context.isStale {
            Text("Ended")
        } else if context.state.phase == .ready {
            if context.attributes.startDate > Date() {
                Text(
                    timerInterval: Date()...context.attributes.startDate,
                    countsDown: true
                )
            } else {
                Text("Now")
            }
        } else if let clockInDate = context.state.clockInDate,
                  clockInDate < context.attributes.endDate {
            Text(
                timerInterval: clockInDate...context.attributes.endDate,
                countsDown: false
            )
        } else {
            Text(context.state.phase.title)
        }
    }

    private func shiftTime(_ attributes: ShiftLiveActivityAttributes) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: attributes.startDate)) – \(formatter.string(from: attributes.endDate))"
    }

    @ViewBuilder
    private func actionLink(
        _ context: ActivityViewContext<ShiftLiveActivityAttributes>
    ) -> some View {
        if context.state.phase == .ready {
            Link(destination: ShiftLiveActivityLinks.action(.start, shiftID: context.attributes.shiftID)) {
                Label("Start", systemImage: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(brand, in: Capsule())
            }
        } else {
            Link(destination: ShiftLiveActivityLinks.action(.end, shiftID: context.attributes.shiftID)) {
                Label("End", systemImage: "stop.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Color.red, in: Capsule())
            }
        }
    }
}

private struct ShiftLiveActivityLockScreenView: View {
    let context: ActivityViewContext<ShiftLiveActivityAttributes>

    private let brand = Color(red: 0.31, green: 0.27, blue: 0.90)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "briefcase.fill")
                    .font(.subheadline)
                    .foregroundStyle(brand)
                Text(context.attributes.companyName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                statusBadge
            }

            HStack(alignment: .center, spacing: 12) {
                Text(shiftTime)
                    .font(.title3.weight(.bold))
                Spacer(minLength: 8)
                actionLink
            }

            HStack(spacing: 14) {
                Text("\(context.state.completedJobs)/\(context.state.totalJobs) Jobs done")
                    .monospacedDigit()
                .foregroundStyle(brand)
                if !context.attributes.location.isEmpty {
                    Label(context.attributes.location, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if context.isStale || context.state.phase != .ready {
                    timer
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var shiftTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: context.attributes.startDate)) – \(formatter.string(from: context.attributes.endDate))"
    }

    private var statusColor: Color {
        switch context.state.phase {
        case .ready: return brand
        case .working: return .green
        case .onBreak: return .orange
        }
    }

    private var phaseIcon: String {
        switch context.state.phase {
        case .ready: return "play.fill"
        case .working: return "briefcase.fill"
        case .onBreak: return "cup.and.saucer.fill"
        }
    }

    private var statusBadge: some View {
        Label(compactStatusTitle, systemImage: phaseIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.14), in: Capsule())
    }

    private var compactStatusTitle: String {
        if context.isStale { return "Ended" }
        switch context.state.phase {
        case .ready: return "Ready"
        case .working: return "Working"
        case .onBreak: return "Break"
        }
    }

    @ViewBuilder
    private var timer: some View {
        if context.isStale {
            Text("Ended")
                .font(.headline)
        } else if context.state.phase == .ready {
            if context.attributes.startDate > Date() {
                Text(
                    timerInterval: Date()...context.attributes.startDate,
                    countsDown: true
                )
                .font(.headline.monospacedDigit())
            } else {
                Text("Start now")
                    .font(.headline)
            }
        } else if let clockInDate = context.state.clockInDate,
                  clockInDate < context.attributes.endDate {
            Text(
                timerInterval: clockInDate...context.attributes.endDate,
                countsDown: false
            )
            .font(.headline.monospacedDigit())
        }
    }

    @ViewBuilder
    private var actionLink: some View {
        if !context.isStale {
            if context.state.phase == .ready {
                Link(destination: ShiftLiveActivityLinks.action(.start, shiftID: context.attributes.shiftID)) {
                    Label("Start Shift", systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(brand, in: Capsule())
                }
            } else {
                Link(destination: ShiftLiveActivityLinks.action(.end, shiftID: context.attributes.shiftID)) {
                    Label("End Shift", systemImage: "stop.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(Color.red, in: Capsule())
                }
            }
        }
    }
}

private enum ShiftLiveActivityLinks {
    enum Action: String {
        case start
        case end
    }

    static func home(shiftID: String) -> URL {
        makeURL(shiftID: shiftID, action: nil)
    }

    static func action(_ action: Action, shiftID: String) -> URL {
        makeURL(shiftID: shiftID, action: action)
    }

    private static func makeURL(shiftID: String, action: Action?) -> URL {
        var components = URLComponents()
        components.scheme = "surafoster"
        components.host = "staff"
        components.path = "/home"
        components.queryItems = [
            URLQueryItem(name: "shiftId", value: shiftID),
        ]
        if let action {
            components.queryItems?.append(URLQueryItem(name: "shiftAction", value: action.rawValue))
        }
        return components.url!
    }
}
