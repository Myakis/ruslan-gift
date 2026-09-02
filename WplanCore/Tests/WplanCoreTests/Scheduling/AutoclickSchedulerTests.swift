import XCTest
@testable import WplanCore

final class AutoclickSchedulerTests: XCTestCase {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // Wednesday 2026-09-02
    func time(hour: Int, minute: Int = 0, day: Int = 2) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    func makeConfiguration(autoStart: Bool = true, autoFinish: Bool = true) -> ScheduleConfiguration {
        ScheduleConfiguration(
            autoStartEnabled: autoStart,
            autoFinishEnabled: autoFinish,
            startTime: ClockTime(hour: 9, minute: 0),
            endTime: ClockTime(hour: 18, minute: 0),
            autoCalculateEightHours: false,
            activeWeekdays: [2, 3, 4, 5, 6] // Mon-Fri; 2026-09-02 is a Wednesday (weekday 4)
        )
    }

    func test_tick_beforeStartTime_isNotDueYet() async throws {
        let client = FakeWplanDayController()
        let network = FakeNetworkAvailability()
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        let result = await scheduler.tick(now: try time(hour: 8, minute: 59))

        XCTAssertEqual(result, .notDueYet)
        XCTAssertTrue(client.startOrFinishDayCalls.isEmpty)
    }

    func test_tick_atStartTime_withNetwork_clicksStart() async throws {
        let client = FakeWplanDayController()
        client.buttonState = WplanButtonState(isVisible: true, isStart: true) // day not started yet
        let network = FakeNetworkAvailability()
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        let result = await scheduler.tick(now: try time(hour: 9, minute: 0))

        XCTAssertEqual(result, .clicked(isStart: true))
        XCTAssertEqual(client.startOrFinishDayCalls, [true])
    }

    func test_tick_atStartTime_withoutNetwork_queues() async throws {
        let client = FakeWplanDayController()
        let network = FakeNetworkAvailability()
        network.isAvailable = false
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        let result = await scheduler.tick(now: try time(hour: 9, minute: 0))

        XCTAssertEqual(result, .queuedNoNetwork(isStart: true))
        XCTAssertTrue(client.startOrFinishDayCalls.isEmpty)
    }

    func test_tick_atStartTime_whenServerAlreadyShowsStarted_doesNotClickAgain() async throws {
        let client = FakeWplanDayController()
        client.buttonState = WplanButtonState(isVisible: true, isStart: false) // already started (site or previous run)
        let network = FakeNetworkAvailability()
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        let result = await scheduler.tick(now: try time(hour: 9, minute: 0))

        XCTAssertEqual(result, .alreadyInDesiredState(isStart: true))
        XCTAssertTrue(client.startOrFinishDayCalls.isEmpty)
    }

    func test_tick_onInactiveWeekday_isNotDueYet() async throws {
        // 2026-09-06 is a Sunday (weekday 1), not in Mon-Fri activeWeekdays
        let client = FakeWplanDayController()
        let network = FakeNetworkAvailability()
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        let result = await scheduler.tick(now: try time(hour: 9, minute: 0, day: 6))

        XCTAssertEqual(result, .notDueYet)
    }

    func test_tick_whenFetchButtonStateThrows_reportsSessionUnavailable() async throws {
        struct Boom: Error {}
        let client = FakeWplanDayController()
        client.fetchButtonStateError = Boom()
        let network = FakeNetworkAvailability()
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        let result = await scheduler.tick(now: try time(hour: 9, minute: 0))

        XCTAssertEqual(result, .sessionUnavailable)
    }

    func test_tick_afterSuccessfulStartClick_doesNotClickAgainOnSubsequentTick() async throws {
        let client = FakeWplanDayController()
        client.buttonState = WplanButtonState(isVisible: true, isStart: true)
        let network = FakeNetworkAvailability()
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        _ = await scheduler.tick(now: try time(hour: 9, minute: 0))
        client.buttonState = WplanButtonState(isVisible: true, isStart: false) // server now reflects the click
        let second = await scheduler.tick(now: try time(hour: 9, minute: 1))

        XCTAssertEqual(second, .alreadyInDesiredState(isStart: true))
        XCTAssertEqual(client.startOrFinishDayCalls, [true])
    }

    func test_tick_atFinishTime_withNetwork_clicksFinish() async throws {
        let client = FakeWplanDayController()
        client.buttonState = WplanButtonState(isVisible: true, isStart: false) // day running
        let network = FakeNetworkAvailability()
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        let result = await scheduler.tick(now: try time(hour: 18, minute: 0))

        XCTAssertEqual(result, .clicked(isStart: false))
        XCTAssertEqual(client.startOrFinishDayCalls, [false])
    }
}
