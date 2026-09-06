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
    private static let startedAtKey = "todayStartedAt"
    private static let finishedAtKey = "todayFinishedAt"
    private static let widgetKind = "WplanRingWidget"
    private static let widgetRefreshInterval: TimeInterval = 5 * 60
    private static let lastHandledResetRequestKey = "lastHandledWidgetResetRequestAt"
    private static let resetRequestPollInterval: TimeInterval = 5

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
    private var resetRequestPollTask: Task<Void, Never>?

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
                autoStartEnabled: true,
                autoFinishEnabled: true,
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

        // Seeding must complete *before* the tick loop's first iteration, or a
        // fresh launch can race its own restored state and re-click start right
        // after finishing (see the finish-persistence fix's commit for the bug
        // this raced into once already). Both seeds and the conditional start()
        // are sequenced in one Task so that can't happen.
        let persistedStartedAt = defaults?.object(forKey: Self.startedAtKey) as? Date
        let persistedFinishedAt = defaults?.object(forKey: Self.finishedAtKey) as? Date
        Task {
            if let persistedStartedAt, Calendar.current.isDateInToday(persistedStartedAt) {
                await initialAgent.seedStartedAt(persistedStartedAt)
            }
            if let persistedFinishedAt, Calendar.current.isDateInToday(persistedFinishedAt) {
                await initialAgent.seedFinishedAt(persistedFinishedAt)
            }
            if shouldRun {
                initialAgent.start()
            }
        }

        startWidgetRefreshLoop()
        startResetRequestPollLoop()
    }

    /// "Включить автоматические клики" is the only automation switch exposed in
    /// Settings — it implies both start and finish, so turning it on also forces
    /// both flags on (covers configs persisted before this UI simplification, which
    /// could have either flag off).
    func setRunning(_ running: Bool) {
        isRunning = running
        defaults?.set(running, forKey: Self.isRunningKey)
        if running {
            if !configuration.autoStartEnabled || !configuration.autoFinishEnabled {
                configuration.autoStartEnabled = true
                configuration.autoFinishEnabled = true
            }
            agent.start()
        } else {
            agent.stop()
        }
    }

    /// Clears today's start/finish bookkeeping (including the guard that blocks a
    /// second automatic start after a finish — see `DayState.autoStartSuppressedToday`)
    /// so the user can deliberately re-run the full automatic cycle again today,
    /// instead of waiting for the calendar day to roll over. Wired to a Settings
    /// action, not exposed as part of the normal automation flow.
    func resetDayState() async {
        await agent.resetDayStateForToday()
        defaults?.removeObject(forKey: Self.startedAtKey)
        defaults?.removeObject(forKey: Self.finishedAtKey)
        manualActionText = "Состояние дня сброшено"
        await refreshWidgetSnapshot()
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
        let now = Date()
        guard configuration.activeWeekdays.contains(Calendar.current.component(.weekday, from: now)) else {
            // Rest day per the schedule — skip the VPN/Wplan round trip entirely
            // and just tell the widget to show "Выходной".
            WidgetSnapshotStore.save(
                WidgetSnapshot(
                    isStart: nil,
                    vpnStatus: .disconnected,
                    startedAt: nil,
                    scheduledFinishAt: nil,
                    finishedAt: nil,
                    isRestDay: true,
                    updatedAt: now
                ),
                appGroupIdentifier: appGroupIdentifier
            )
            WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
            return
        }
        let vpnStatus = await vpnChecker.currentStatus()
        let isStart: Bool?
        if let state = try? await statusClient.fetchButtonState() {
            isStart = state.isStart
        } else {
            isStart = WidgetSnapshotStore.load(appGroupIdentifier: appGroupIdentifier)?.isStart
        }
        let startedAt = await agent.currentStartedAt()
        if let startedAt {
            defaults?.set(startedAt, forKey: Self.startedAtKey)
        }
        let finishedAt = await agent.currentFinishedAt()
        if let finishedAt {
            defaults?.set(finishedAt, forKey: Self.finishedAtKey)
        }
        let scheduledFinishAt = await agent.currentScheduledFinishAt(now: now)
        WidgetSnapshotStore.save(
            WidgetSnapshot(
                isStart: isStart,
                vpnStatus: vpnStatus,
                startedAt: startedAt,
                scheduledFinishAt: scheduledFinishAt,
                finishedAt: finishedAt,
                updatedAt: now
            ),
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

    /// The widget extension can't reach the host app's live `AutoclickScheduler`
    /// directly (separate process) — its reset button just leaves a timestamp in
    /// the App Group container via `WidgetResetRequestStore`. This loop is the
    /// side that actually applies it, polling far more often than the network-heavy
    /// `widgetRefreshTask` since it only touches local UserDefaults.
    private func startResetRequestPollLoop() {
        resetRequestPollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.applyPendingResetRequestIfAny()
                try? await Task.sleep(nanoseconds: UInt64(Self.resetRequestPollInterval * 1_000_000_000))
            }
        }
    }

    private func applyPendingResetRequestIfAny() async {
        guard let requestedAt = WidgetResetRequestStore.pendingRequestAt(appGroupIdentifier: appGroupIdentifier),
              requestedAt > (defaults?.object(forKey: Self.lastHandledResetRequestKey) as? Date ?? .distantPast)
        else { return }
        defaults?.set(requestedAt, forKey: Self.lastHandledResetRequestKey)
        await resetDayState()
    }

    private func persistConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults?.set(data, forKey: Self.configurationKey)
        }
    }
}
