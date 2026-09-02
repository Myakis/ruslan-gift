import Foundation
import WplanCore

/// Owns the schedule (persisted to UserDefaults in the App Group suite) and the
/// running `WplanAutomationAgent`. Manual clicks route through here (not through a
/// separate raw `WplanClient`) so the scheduler's own day-bookkeeping stays in sync
/// — a manual click must cancel today's automatic click for that action, per spec.
@MainActor
final class AutomationController: ObservableObject {
    private static let configurationKey = "scheduleConfiguration"
    private static let isRunningKey = "automationIsRunning"

    @Published var configuration: ScheduleConfiguration {
        didSet {
            persistConfiguration()
            Task { await agent.updateConfiguration(configuration) }
        }
    }
    @Published var isRunning: Bool
    @Published var manualActionText: String?
    @Published var isPerformingManualAction = false

    private let defaults: UserDefaults?
    private let agent: WplanAutomationAgent

    init(appGroupIdentifier: String) {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        self.defaults = defaults

        let initialConfiguration: ScheduleConfiguration
        if let data = defaults?.data(forKey: Self.configurationKey),
           let decoded = try? JSONDecoder().decode(ScheduleConfiguration.self, from: data) {
            initialConfiguration = decoded
        } else {
            initialConfiguration = ScheduleConfiguration(
                autoStartEnabled: false,
                autoFinishEnabled: false,
                startTime: ClockTime(hour: 9, minute: 0),
                endTime: ClockTime(hour: 18, minute: 0),
                autoCalculateEightHours: false,
                activeWeekdays: [2, 3, 4, 5, 6] // Mon-Fri
            )
        }
        configuration = initialConfiguration

        let initialAgent = WplanAutomation.makeAgent(appGroupIdentifier: appGroupIdentifier, configuration: initialConfiguration)
        agent = initialAgent
        let shouldRun = defaults?.bool(forKey: Self.isRunningKey) ?? false
        isRunning = shouldRun
        if shouldRun {
            initialAgent.start()
        }
    }

    func setRunning(_ running: Bool) {
        isRunning = running
        defaults?.set(running, forKey: Self.isRunningKey)
        if running {
            agent.start()
        } else {
            agent.stop()
        }
    }

    func performManualClick(isStart: Bool) async {
        isPerformingManualAction = true
        defer { isPerformingManualAction = false }
        do {
            try await agent.performManualClick(isStart: isStart)
            manualActionText = isStart ? "Начало дня отправлено" : "Завершение дня отправлено"
        } catch {
            manualActionText = "Ошибка: \(describeWplanError(error))"
        }
    }

    private func persistConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults?.set(data, forKey: Self.configurationKey)
        }
    }
}
