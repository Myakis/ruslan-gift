import SwiftUI
import WplanCore

private let weekdayLabels: [(value: Int, label: String)] = [
    (2, "пн"), (3, "вт"), (4, "ср"), (5, "чт"), (6, "пт"), (7, "сб"), (1, "вс")
]

struct SettingsView: View {
    @ObservedObject var automation: AutomationController

    var body: some View {
        Form {
            Section("Автоматизация") {
                Toggle("Включить автоматические клики", isOn: Binding(
                    get: { automation.isRunning },
                    set: { automation.setRunning($0) }
                ))

                Toggle("Авто начало дня", isOn: Binding(
                    get: { automation.configuration.autoStartEnabled },
                    set: { automation.configuration.autoStartEnabled = $0 }
                ))
                Toggle("Авто завершение дня", isOn: Binding(
                    get: { automation.configuration.autoFinishEnabled },
                    set: { automation.configuration.autoFinishEnabled = $0 }
                ))
                Toggle("Авто расчёт 8 часов от начала", isOn: Binding(
                    get: { automation.configuration.autoCalculateEightHours },
                    set: { automation.configuration.autoCalculateEightHours = $0 }
                ))
            }

            Section("Время") {
                DatePicker(
                    "Начало",
                    selection: clockTimeBinding(\.startTime),
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Окончание",
                    selection: clockTimeBinding(\.endTime),
                    displayedComponents: .hourAndMinute
                )
                .disabled(automation.configuration.autoCalculateEightHours)
            }

            Section("Дни недели") {
                HStack {
                    ForEach(weekdayLabels, id: \.value) { day in
                        let isActive = automation.configuration.activeWeekdays.contains(day.value)
                        Button(day.label) {
                            if isActive {
                                automation.configuration.activeWeekdays.remove(day.value)
                            } else {
                                automation.configuration.activeWeekdays.insert(day.value)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(isActive ? .green : .secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
    }

    /// Bridges `ScheduleConfiguration`'s `ClockTime` (hour/minute only) to the `Date`
    /// SwiftUI's `DatePicker` needs — the calendar day is irrelevant and dropped.
    private func clockTimeBinding(_ keyPath: WritableKeyPath<ScheduleConfiguration, ClockTime>) -> Binding<Date> {
        Binding(
            get: {
                let time = automation.configuration[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                automation.configuration[keyPath: keyPath] = ClockTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
            }
        )
    }
}
