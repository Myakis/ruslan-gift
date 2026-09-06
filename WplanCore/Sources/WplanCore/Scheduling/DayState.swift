import Foundation

public struct DayState {
    private(set) var calendarDay: Date
    public private(set) var startHandledManually: Bool = false
    public private(set) var finishHandledManually: Bool = false
    public private(set) var startPerformedAt: Date?
    public private(set) var finishPerformedAt: Date?
    /// True once today's cycle has reached "finished" — via an automatic click, a
    /// manual click, or discovering the server already showed it finished. Blocks
    /// the *automatic* start branch from firing again today, without touching
    /// `startPerformedAt` (which must keep reflecting the real start time for the
    /// progress-ring calculation). Needed because the Wplan API's "not started"
    /// button state is indistinguishable between "never started today" and
    /// "already finished today" — a relaunched process has no other way to tell
    /// the two apart, and would otherwise re-click start after every finish.
    public private(set) var autoStartSuppressedToday = false

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

    /// Records that today's day has reached "finished" — automatically or
    /// manually, or discovered already-finished on the server. See
    /// `autoStartSuppressedToday`'s doc comment for why this also suppresses
    /// automatic starts for the rest of the day.
    public mutating func recordFinishPerformed(at date: Date) {
        finishPerformedAt = date
        autoStartSuppressedToday = true
    }

    /// Manually clears today's bookkeeping without waiting for the calendar day to
    /// roll over — lets the user deliberately re-run the full automatic cycle
    /// (start + finish) more than once in the same day, e.g. after testing or
    /// after a mistaken finish, overriding the `autoStartSuppressedToday` guard.
    public mutating func resetForToday() {
        startHandledManually = false
        finishHandledManually = false
        startPerformedAt = nil
        finishPerformedAt = nil
        autoStartSuppressedToday = false
    }

    public mutating func resetIfNewDay(now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        guard today != calendarDay else { return }
        calendarDay = today
        startHandledManually = false
        finishHandledManually = false
        startPerformedAt = nil
        finishPerformedAt = nil
        autoStartSuppressedToday = false
    }
}
