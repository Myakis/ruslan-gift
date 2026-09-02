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
