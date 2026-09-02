import XCTest
@testable import WplanCore

final class DayStateTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func test_freshDayState_hasNothingHandled() {
        let state = DayState(calendarDay: Date(), calendar: calendar)
        XCTAssertFalse(state.startHandledManually)
        XCTAssertFalse(state.finishHandledManually)
        XCTAssertNil(state.startPerformedAt)
    }

    func test_markStartHandled_recordsTimestampAndFlag() {
        var state = DayState(calendarDay: Date(), calendar: calendar)
        let now = Date()

        state.markStartHandled(at: now)

        XCTAssertTrue(state.startHandledManually)
        XCTAssertEqual(state.startPerformedAt, now)
    }

    func test_resetIfNewDay_clearsStateWhenCalendarDayChanges() throws {
        let day1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 10)))
        let day2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 9)))
        var state = DayState(calendarDay: day1, calendar: calendar)
        state.markStartHandled(at: day1)

        state.resetIfNewDay(now: day2, calendar: calendar)

        XCTAssertFalse(state.startHandledManually)
        XCTAssertNil(state.startPerformedAt)
    }

    func test_resetIfNewDay_keepsStateWithinSameCalendarDay() throws {
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 9)))
        let afternoon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 15)))
        var state = DayState(calendarDay: morning, calendar: calendar)
        state.markStartHandled(at: morning)

        state.resetIfNewDay(now: afternoon, calendar: calendar)

        XCTAssertTrue(state.startHandledManually)
    }
}
