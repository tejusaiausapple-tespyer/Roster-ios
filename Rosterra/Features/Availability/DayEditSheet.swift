import SwiftUI

/// Bottom sheet to edit a single day's availability. Reduces taps versus the
/// web app's always-expanded 7-day form: pick availability, all-day, or a custom
/// time range in one focused surface.
struct DayEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let weekday: Weekday
    let dateKey: String
    @Binding var day: DayAvailability

    @State private var available: Bool
    @State private var allDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var error: String?

    init(weekday: Weekday, dateKey: String, day: Binding<DayAvailability>) {
        self.weekday = weekday
        self.dateKey = dateKey
        _day = day
        let value = day.wrappedValue
        _available = State(initialValue: value.available)
        _allDay = State(initialValue: value.allDay)
        _start = State(initialValue: TimeConvert.date(from: value.start ?? "09:00") ?? Date())
        _end = State(initialValue: TimeConvert.date(from: value.end ?? "17:00") ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        Toggle(isOn: $available.animation()) {
                            Label("Available", systemImage: "checkmark.circle")
                                .font(.body.weight(.medium))
                        }
                        .tint(Theme.accent)
                    }

                    if available {
                        Card {
                            Toggle(isOn: $allDay.animation()) {
                                Label("Available all day", systemImage: "sun.max")
                                    .font(.body.weight(.medium))
                            }
                            .tint(Theme.brand)
                        }

                        if !allDay {
                            Card {
                                VStack(spacing: 14) {
                                    HStack {
                                        Text("From").font(.subheadline.weight(.medium))
                                        Spacer()
                                        DatePicker("", selection: $start, displayedComponents: .hourAndMinute).labelsHidden()
                                    }
                                    Divider().overlay(Theme.separator)
                                    HStack {
                                        Text("Until").font(.subheadline.weight(.medium))
                                        Spacer()
                                        DatePicker("", selection: $end, displayedComponents: .hourAndMinute).labelsHidden()
                                    }
                                }
                            }
                        }
                    } else {
                        Text("You'll be marked as unavailable for this day.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error {
                        Banner(kind: .error, title: error)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(RosterFormat.weekdayLong(dateKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func apply() {
        let startHHmm = TimeConvert.hhmm(from: start)
        let endHHmm = TimeConvert.hhmm(from: end)
        if available && !allDay && startHHmm >= endHHmm {
            error = "End time must be after start time."
            Haptics.error()
            return
        }
        day = DayAvailability(
            available: available,
            allDay: allDay,
            start: available && !allDay ? startHHmm : nil,
            end: available && !allDay ? endHHmm : nil
        )
        Haptics.light()
        dismiss()
    }
}
