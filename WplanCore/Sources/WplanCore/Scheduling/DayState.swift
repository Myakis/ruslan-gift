import Foundation

public struct DayState {
    private(set) var calendarDay: Date
    public private(set) var startHandledManually: Bool = false
    public private(set) var finishHandledManually: Bool = false
    public private(set) var startPerformedAt: Date?

    public init(calendarDay: Date, calendar: Calendar) {
        self.calendarDay = calendar.startOfDay(for: calendarDay)
    }

    public mutating func markStartHandled(at date: Date) {
        startHandledManually = true
        startPerformedAt = date
    }

    /// Records that an *automatic* start click succeeded, without marking it as a
    /// manual override — the automatic path must still be re-evaluated (and dedup
    /// against the server) on later ticks, unlike a manual click which overrides
    /// the schedule for the rest of the day.
    public mutating func recordStartPerformed(at date: Date) {
        startPerformedAt = date
    }

    public mutating func markFinishHandled() {
        finishHandledManually = true
    }

    public mutating func resetIfNewDay(now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        guard today != calendarDay else { return }
        calendarDay = today
        startHandledManually = false
        finishHandledManually = false
        startPerformedAt = nil
    }
}
