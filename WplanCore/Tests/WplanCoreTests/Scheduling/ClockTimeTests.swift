import XCTest
@testable import WplanCore

final class ClockTimeTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func test_date_onDayOf_producesSameCalendarDayAtGivenTime() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 14, minute: 46)))
        let clockTime = ClockTime(hour: 9, minute: 0)

        let result = try XCTUnwrap(clockTime.date(onDayOf: reference, calendar: calendar))

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 2)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    func test_equality_comparesHourAndMinute() {
        XCTAssertEqual(ClockTime(hour: 9, minute: 0), ClockTime(hour: 9, minute: 0))
        XCTAssertNotEqual(ClockTime(hour: 9, minute: 0), ClockTime(hour: 9, minute: 1))
    }
}
