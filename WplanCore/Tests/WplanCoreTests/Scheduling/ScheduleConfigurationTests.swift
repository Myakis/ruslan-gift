import XCTest
@testable import WplanCore

final class ScheduleConfigurationTests: XCTestCase {
    func test_init_storesAllFields() {
        let config = ScheduleConfiguration(
            autoStartEnabled: true,
            autoFinishEnabled: true,
            startTime: ClockTime(hour: 9, minute: 0),
            endTime: ClockTime(hour: 18, minute: 0),
            autoCalculateEightHours: false,
            activeWeekdays: [2, 3, 4, 5, 6] // Mon-Fri
        )

        XCTAssertTrue(config.autoStartEnabled)
        XCTAssertTrue(config.autoFinishEnabled)
        XCTAssertEqual(config.startTime, ClockTime(hour: 9, minute: 0))
        XCTAssertEqual(config.endTime, ClockTime(hour: 18, minute: 0))
        XCTAssertFalse(config.autoCalculateEightHours)
        XCTAssertEqual(config.activeWeekdays, [2, 3, 4, 5, 6])
    }
}
