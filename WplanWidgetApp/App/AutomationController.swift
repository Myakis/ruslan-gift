import Foundation
import WidgetKit
import WplanCore

/// Owns the schedule (persisted to UserDefaults in the App Group suite) and the
/// running `WplanAutomationAgent`. Manual clicks route through here (not through a
/// separate raw `WplanClient`) so the scheduler's own day-bookkeeping stays in sync
/// — a manual click must cancel today's automatic click for that action, per spec.
///
/// Also periodically refreshes the shared `WidgetSnapshot` the widget extension
/// reads — the widget can't cheaply call WplanClient on its own, so the host app
/// is the one source of truth writing into the App Group container.
@MainActor
final class AutomationController: ObservableObject {
    private static let configurationKey = "scheduleConfiguration"
    private static let isRunningKey = "automationIsRunning"
    private static let widgetKind = "WplanRingWidget"
    private static let widgetRefreshInterval: TimeInterval = 5 * 60

    @Published var configuration: ScheduleConfiguration {
        didSet {
            persistConfiguration()
            Task { await agent.updateConfiguration(configuration) }
        }
    }
    @Published var isRunning: Bool
    @Published var manualActionText: String?
    @Published var isPerformingManualAction = false

    private let appGroupIdentifier: String
    private let defaults: UserDefaults?
    private let agent: WplanAutomationAgent
    /// Separate from the agent's own client — only used for the periodic widget
    /// snapshot read, which happens on its own cadence independent of the schedule.
    private let statusClient: WplanClient
    private let vpnChecker = VPNNetworkChecker()
    private var widgetRefreshTask: Task<Void, Never>?

    init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
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
        statusClient = WplanClient(session: WplanSessionFactory.makeSession(appGroupIdentifier: appGroupIdentifier))
        let shouldRun = defaults?.bool(forKey: Self.isRunningKey) ?? false
        isRunning = shouldRun
        if shouldRun {
            initialAgent.start()
        }

        startWidgetRefreshLoop()
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
            await refreshWidgetSnapshot()
        } catch {
            manualActionText = "Ошибка: \(describeWplanError(error))"
        }
    }

    /// Fetches the current VPN status and (VPN permitting) day status, writes them
    /// where the widget can read them, then asks WidgetKit to redraw. VPN status is
    /// always written, even when Wplan itself can't be reached — that's exactly the
    /// state the widget most needs to show (design doc screen `3a`). Day status
    /// falls back to whatever was last known if this particular fetch fails, rather
    /// than reporting a false "not started".
    func refreshWidgetSnapshot() async {
        let vpnStatus = await vpnChecker.currentStatus()
        let isStart: Bool?
        if let state = try? await statusClient.fetchButtonState() {
            isStart = state.isStart
        } else {
            isStart = WidgetSnapshotStore.load(appGroupIdentifier: appGroupIdentifier)?.isStart
        }
        WidgetSnapshotStore.save(
            WidgetSnapshot(isStart: isStart, vpnStatus: vpnStatus, updatedAt: Date()),
            appGroupIdentifier: appGroupIdentifier
        )
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }

    private func startWidgetRefreshLoop() {
        widgetRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshWidgetSnapshot()
                try? await Task.sleep(nanoseconds: UInt64(Self.widgetRefreshInterval * 1_000_000_000))
            }
        }
    }

    private func persistConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults?.set(data, forKey: Self.configurationKey)
        }
    }
}
