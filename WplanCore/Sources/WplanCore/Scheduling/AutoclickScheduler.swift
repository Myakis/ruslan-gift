import Foundation

public enum AutoclickTickResult: Equatable {
    case notDueYet
    case queuedNoNetwork(isStart: Bool)
    case alreadyInDesiredState(isStart: Bool)
    case clicked(isStart: Bool)
    case sessionUnavailable
}

public actor AutoclickScheduler {
    private let client: any WplanDayControlling
    private let network: any NetworkAvailabilityChecking
    private var configuration: ScheduleConfiguration
    private let calendar: Calendar
    private var dayState: DayState

    public init(
        client: any WplanDayControlling,
        network: any NetworkAvailabilityChecking,
        configuration: ScheduleConfiguration,
        calendar: Calendar = .current
    ) {
        self.client = client
        self.network = network
        self.configuration = configuration
        self.calendar = calendar
        self.dayState = DayState(calendarDay: Date(), calendar: calendar)
    }

    public func updateConfiguration(_ configuration: ScheduleConfiguration) {
        self.configuration = configuration
    }

    /// When today's start click (automatic or manual) actually happened, if at all —
    /// lets a caller (the widget snapshot writer) show progress toward the scheduled
    /// finish without needing a real "hours worked" value from the Wplan API.
    public func currentStartedAt() -> Date? {
        dayState.startPerformedAt
    }

    /// The scheduled finish instant for today, given the current configuration and
    /// (if `autoCalculateEightHours` is on) today's recorded start — `nil` if there's
    /// nothing to compute from yet (8h mode, no start recorded this process).
    public func currentScheduledFinishAt(now: Date) -> Date? {
        effectiveFinishTime(now: now)
    }

    /// Restores a start timestamp recorded by a *previous process* (see
    /// `DayState.startPerformedAt`'s doc comment — it only lives in memory
    /// otherwise, so a relaunch mid-day would otherwise forget it entirely).
    /// A no-op if `date` isn't within today's calendar day.
    public func seedStartedAt(_ date: Date, now: Date) {
        dayState.resetIfNewDay(now: now, calendar: calendar)
        guard calendar.isDate(date, inSameDayAs: now) else { return }
        dayState.recordStartPerformed(at: date)
    }

    /// When today's day was finished, if at all — see `DayState.finishPerformedAt`.
    public func currentFinishedAt() -> Date? {
        dayState.finishPerformedAt
    }

    /// Restores a finish timestamp recorded by a *previous process*, and — same as
    /// the original recording — suppresses further automatic start clicks today.
    /// A no-op if `date` isn't within today's calendar day. Without this, a
    /// relaunch after finishing (later the same day, still within active hours)
    /// would re-click start: the server's "not started" button state can't tell
    /// "never started today" apart from "already finished today".
    public func seedFinishedAt(_ date: Date, now: Date) {
        dayState.resetIfNewDay(now: now, calendar: calendar)
        guard calendar.isDate(date, inSameDayAs: now) else { return }
        dayState.recordFinishPerformed(at: date)
    }

    public func tick(now: Date) async -> AutoclickTickResult {
        dayState.resetIfNewDay(now: now, calendar: calendar)

        guard configuration.activeWeekdays.contains(calendar.component(.weekday, from: now)) else {
            return .notDueYet
        }

        var startResult: AutoclickTickResult?
        if configuration.autoStartEnabled,
           !dayState.startHandledManually,
           !dayState.autoStartSuppressedToday,
           let startAt = configuration.startTime.date(onDayOf: now, calendar: calendar),
           now >= startAt {
            let result = await performIfNeeded(isStart: true, now: now)
            switch result {
            case .clicked, .queuedNoNetwork, .sessionUnavailable:
                return result
            case .alreadyInDesiredState, .notDueYet:
                startResult = result
            }
        }

        if configuration.autoFinishEnabled,
           !dayState.finishHandledManually,
           let finishAt = effectiveFinishTime(now: now),
           now >= finishAt {
            return await performIfNeeded(isStart: false, now: now)
        }

        return startResult ?? .notDueYet
    }

    public func performManualClick(isStart: Bool, now: Date) async throws {
        dayState.resetIfNewDay(now: now, calendar: calendar)
        try await client.startOrFinishDay(isStart: isStart)
        if isStart {
            dayState.markStartHandled(at: now)
        } else {
            dayState.markFinishHandled()
            dayState.recordFinishPerformed(at: now)
        }
    }

    private func effectiveFinishTime(now: Date) -> Date? {
        if configuration.autoCalculateEightHours, let startedAt = dayState.startPerformedAt {
            return startedAt.addingTimeInterval(8 * 60 * 60)
        }
        return configuration.endTime.date(onDayOf: now, calendar: calendar)
    }

    private func performIfNeeded(isStart: Bool, now: Date) async -> AutoclickTickResult {
        guard await network.isNetworkAvailable() else {
            return .queuedNoNetwork(isStart: isStart)
        }

        let state: WplanButtonState
        do {
            state = try await client.fetchButtonState()
        } catch {
            return .sessionUnavailable
        }

        guard state.isStart == isStart else {
            if !isStart { dayState.recordFinishPerformed(at: now) }
            return .alreadyInDesiredState(isStart: isStart)
        }

        do {
            try await client.startOrFinishDay(isStart: isStart)
        } catch {
            return .sessionUnavailable
        }

        if isStart {
            dayState.recordStartPerformed(at: now)
        } else {
            dayState.recordFinishPerformed(at: now)
        }
        return .clicked(isStart: isStart)
    }
}
