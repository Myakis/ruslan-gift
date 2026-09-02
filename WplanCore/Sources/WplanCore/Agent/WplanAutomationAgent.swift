import Foundation

/// Drives `AutoclickScheduler.tick()` on a repeating interval — the background
/// timer the scheduler's own docs describe as "something external" wiring it up.
/// Runs as a plain Swift Concurrency loop so it works the same inside a menu-bar
/// app, a widget extension's background refresh, or (for manual testing) a CLI.
public final class WplanAutomationAgent {
    private let scheduler: AutoclickScheduler
    private let tickInterval: TimeInterval
    private var loopTask: Task<Void, Never>?

    public init(scheduler: AutoclickScheduler, tickInterval: TimeInterval = 30) {
        self.scheduler = scheduler
        self.tickInterval = tickInterval
    }

    /// Starts the tick loop. Safe to call again after `stop()`; a no-op if already running.
    public func start() {
        guard loopTask == nil else { return }
        let scheduler = self.scheduler
        let interval = self.tickInterval
        loopTask = Task {
            while !Task.isCancelled {
                _ = await scheduler.tick(now: Date())
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Bypasses the schedule and clicks immediately — wired to the popover's
    /// "Начать/Завершить сейчас" action. Also cancels today's automatic click for
    /// that action (via the scheduler's own `performManualClick`), so a manual
    /// click and the timer loop never race each other.
    public func performManualClick(isStart: Bool) async throws {
        try await scheduler.performManualClick(isStart: isStart, now: Date())
    }

    /// Applies a new schedule to the already-running loop (e.g. after editing
    /// Settings) without needing to stop/recreate the agent.
    public func updateConfiguration(_ configuration: ScheduleConfiguration) async {
        await scheduler.updateConfiguration(configuration)
    }
}

/// Composition root: builds the full WplanCore stack (session, client, VPN check,
/// scheduler, timer loop) from just an App Group id and a schedule.
public enum WplanAutomation {
    public static func makeAgent(
        appGroupIdentifier: String?,
        configuration: ScheduleConfiguration,
        tickInterval: TimeInterval = 30
    ) -> WplanAutomationAgent {
        let session = WplanSessionFactory.makeSession(appGroupIdentifier: appGroupIdentifier)
        let client = WplanClient(session: session)
        let network = VPNNetworkChecker(probeURL: WplanClient.defaultBaseURL, session: session)
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: configuration)
        return WplanAutomationAgent(scheduler: scheduler, tickInterval: tickInterval)
    }
}
