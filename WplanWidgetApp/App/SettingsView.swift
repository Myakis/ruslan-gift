import SwiftUI
import WplanCore

private let weekdayLabels: [(value: Int, label: String)] = [
    (2, "пн"), (3, "вт"), (4, "ср"), (5, "чт"), (6, "пт"), (7, "сб"), (1, "вс")
]

struct SettingsView: View {
    @ObservedObject var automation: AutomationController
    @StateObject private var status = MenuBarStatusModel()
    @Environment(\.dismissWindow) private var dismissWindow
    /// Ticks every second so "Осталось"/"Время" move smoothly, independent of
    /// `status`'s own (much coarser) 15s snapshot refresh.
    @State private var now = Date()
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isRunning: Bool? {
        status.snapshot?.isStart.map { !$0 }
    }

    private var statusDotColor: Color {
        MenuBarStyle.vpnColor(status.snapshot?.vpnStatus ?? .disconnected, isRunning: isRunning)
    }

    private var statusHeadline: String {
        switch status.snapshot?.vpnStatus ?? .disconnected {
        case .disconnected: return "VPN выкл."
        case .connecting: return "Подключение…"
        case .connected:
            switch isRunning {
            case .some(true): return "День идёт"
            case .some(false): return "День не начат"
            case .none: return "Нет данных"
            }
        }
    }

    private var remainingText: String {
        guard isRunning == true, let finishAt = status.snapshot?.scheduledFinishAt else { return "—" }
        let remaining = max(0, finishAt.timeIntervalSince(now))
        let totalSeconds = Int(remaining)
        return String(format: "%d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    private var currentTimeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusHeader

                sectionBlock(title: "Автоматизация") {
                    toggleRow("Включить автоматические клики", isOn: Binding(
                        get: { automation.isRunning },
                        set: { automation.setRunning($0) }
                    ))
                    toggleRow("Авто расчёт 8 часов от начала", isOn: Binding(
                        get: { automation.configuration.autoCalculateEightHours },
                        set: { automation.configuration.autoCalculateEightHours = $0 }
                    ))
                }

                sectionBlock(title: "Время") {
                    HStack(spacing: 10) {
                        timeBox(label: "Начало", selection: clockTimeBinding(\.startTime))
                        timeBox(label: "Окончание", selection: clockTimeBinding(\.endTime))
                            .disabled(automation.configuration.autoCalculateEightHours)
                            .opacity(automation.configuration.autoCalculateEightHours ? 0.4 : 1)
                    }

                    HStack(spacing: 6) {
                        ForEach(weekdayLabels, id: \.value) { day in
                            let isActive = automation.configuration.activeWeekdays.contains(day.value)
                            Button(day.label) {
                                if isActive {
                                    automation.configuration.activeWeekdays.remove(day.value)
                                } else {
                                    automation.configuration.activeWeekdays.insert(day.value)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isActive ? Color.green.opacity(0.18) : Color.primary.opacity(0.05))
                            )
                            .foregroundStyle(isActive ? .green : .secondary)
                        }
                    }
                }

                Button("Готово") { dismissWindow(id: "settings") }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
            }
            .padding(16)
        }
        .frame(width: 340, height: 500)
        .onReceive(clockTimer) { now = $0 }
    }

    private var statusHeader: some View {
        HStack(spacing: 0) {
            statColumn(label: "СТАТУС") {
                HStack(spacing: 5) {
                    Circle().fill(statusDotColor).frame(width: 6, height: 6)
                    Text(statusHeadline)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Divider().frame(height: 30)
            statColumn(label: "ОСТАЛОСЬ") {
                Text(remainingText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRunning == true ? .green : .secondary)
            }
            Divider().frame(height: 30)
            statColumn(label: "ВРЕМЯ") {
                Text(currentTimeText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
        }
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func statColumn(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private func sectionBlock(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
            VStack(spacing: 8) {
                content()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.system(size: 12.5))
        }
        .toggleStyle(.switch)
        .tint(.green)
    }

    private func timeBox(label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
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
