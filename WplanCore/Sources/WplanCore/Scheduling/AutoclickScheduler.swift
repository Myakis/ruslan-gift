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

    public func tick(now: Date) async -> AutoclickTickResult {
        dayState.resetIfNewDay(now: now, calendar: calendar)

        guard configuration.activeWeekdays.contains(calendar.component(.weekday, from: now)) else {
            return .notDueYet
        }

        var startResult: AutoclickTickResult?
        if configuration.autoStartEnabled,
           !dayState.startHandledManually,
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
            return .alreadyInDesiredState(isStart: isStart)
        }

        do {
            try await client.startOrFinishDay(isStart: isStart)
        } catch {
            return .sessionUnavailable
        }

        if isStart {
            dayState.recordStartPerformed(at: now)
        }
        return .clicked(isStart: isStart)
    }
}
