# Autoclick Scheduler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `AutoclickScheduler` to `WplanCore` that decides, on each `tick()`, whether to click "start day" or "finish day" — based on a configurable schedule, the server's own button state (for dedup), and network availability (for queueing) — and exposes a manual override path. Still no UI, no real OS timer, no real VPN check: this is the decision engine those will drive and depend on.

**Architecture:** `AutoclickScheduler` is a Swift `actor` (all its state — day bookkeeping, config — is mutated only through its own methods, so a later timer-driven caller and a manual-click caller from the UI can both call into it safely without external locking). It depends on two small protocols instead of concrete types — `WplanDayControlling` (satisfied by `WplanClient`) and `NetworkAvailabilityChecking` (satisfied by the VPN detector in a later plan) — so this plan's tests never touch the network, and the later VPN-detection plan only has to implement one method to plug in.

**Tech Stack:** Swift 5.9+ (Swift Concurrency: `actor`), `XCTest`, `Foundation` (`Calendar`, `Date`). Builds on `WplanCore` from `docs/superpowers/plans/2026-09-02-wplan-api-foundation.md` (already implemented — `WplanClient`, `WplanButtonState`).

**Spec:** `Функционал приложения IFMO/Time Widget Concepts.dc.html`, section "ПРАВИЛА АВТОКЛИКОВ" (screen `4a`):
- Клик «Начать» — в заданный час:минуту, только в выбранные дни недели.
- Клик «Завершить» — по заданному часу либо по «авто расчёту 8 часов» от фактического начала.
- Если нет VPN/сессии в момент X — задача не теряется, ставится в очередь, выполняется при первой возможности.
- Повторный клик не отправляется, если статус на сайте уже «день начат/завершён».
- Ручное «Начать/Завершить сейчас» доступно всегда и отменяет запланированный клик на сегодня.

## Global Constraints

- No OS-level timer/scheduling in this plan — `tick()` is called by something external (a later plan wires a `Timer`/background task to call it, e.g. every 30–60s). This plan only tests the decision logic by calling `tick()` directly with an injected clock.
- No real network/VPN check — `NetworkAvailabilityChecking` is a protocol; this plan's tests use a fake, the real VPN-detection plan supplies the production implementation.
- Dedup against the **server's** state (`WplanClient.fetchButtonState()`), not just local memory — matches the spec's "повторный клик не отправляется, если статус уже начат/завершён" (a click already made from the website itself, or from a previous app run, must still be respected).

## Amendment (found while implementing Task 6)

`AutoclickScheduler.tick()` evaluates start and finish semi-independently within one call rather than returning on the first branch that is "due": if the start branch resolves to `.alreadyInDesiredState`/wasn't due, evaluation falls through to check finish in the same tick (only `.clicked`/`.queuedNoNetwork`/`.sessionUnavailable` from the start branch short-circuit the whole call). This was required so a tick that lands exactly on the finish time still fires the finish click even though the start branch (due to `now >= startTime` holding for the entire rest of the day) is also "due" and resolves first. `DayState` gained `recordStartPerformed(at:)` — distinct from `markStartHandled(at:)` — so a *successful automatic* start click records the timestamp (for the 8-hour calculation) without setting the manual-override flag; only `performManualClick` sets that flag.

## Known Limitation (carried forward)

The Wplan API gives no timestamp for when the day actually started (`StartOrFinishButtonState` only returns `isVisible`/`isStart` booleans — see the prior plan's "Known Limitation"). So "авто расчёт 8 часов от фактического начала" can only use the *this app instance's own* record of when it last successfully triggered a start click (`DayState.startPerformedAt`), not a true source-of-truth timestamp from the server. If the day was started by clicking directly on the Wplan website, or by a previous run of the app before this feature existed, `startPerformedAt` will be `nil` and the 8-hour auto-calculation silently has nothing to compute from until this app performs a start click itself. Follow-up (not in this plan): capture a Wplan query that returns the actual day-start timestamp, then switch `DayState` to read it from the server on `tick()` instead of recording it locally.

---

## File Structure

```
WplanCore/Sources/WplanCore/Scheduling/
├── ClockTime.swift                  — hour:minute value + Date arithmetic for "is it past this time today"
├── ScheduleConfiguration.swift      — autoStart/autoFinish flags, times, active weekdays
├── NetworkAvailabilityChecking.swift — protocol the VPN-detection plan will implement
├── WplanDayControlling.swift        — protocol WplanClient already satisfies; lets scheduler tests use a fake
├── DayState.swift                   — per-calendar-day bookkeeping: manual overrides, recorded start time
└── AutoclickScheduler.swift         — the actor: tick(), performManualClick(isStart:)

WplanCore/Tests/WplanCoreTests/Scheduling/
├── ClockTimeTests.swift
├── ScheduleConfigurationTests.swift
├── DayStateTests.swift
├── Fakes/FakeWplanDayController.swift
├── Fakes/FakeNetworkAvailability.swift
└── AutoclickSchedulerTests.swift
```

## Interfaces produced (for later plans — VPN detector, timer driver, widget/menu bar UI — to consume)

```swift
public struct ClockTime: Equatable { public let hour: Int; public let minute: Int
    public init(hour: Int, minute: Int)
    public func date(onDayOf reference: Date, calendar: Calendar) -> Date?
}

public struct ScheduleConfiguration: Equatable {
    public var autoStartEnabled: Bool
    public var autoFinishEnabled: Bool
    public var startTime: ClockTime
    public var endTime: ClockTime
    public var autoCalculateEightHours: Bool
    public var activeWeekdays: Set<Int>   // Calendar.component(.weekday, from:) values: 1 = Sunday ... 7 = Saturday
    public init(autoStartEnabled: Bool, autoFinishEnabled: Bool, startTime: ClockTime, endTime: ClockTime, autoCalculateEightHours: Bool, activeWeekdays: Set<Int>)
}

public protocol WplanDayControlling {
    func fetchButtonState() async throws -> WplanButtonState
    func startOrFinishDay(isStart: Bool) async throws
}
extension WplanClient: WplanDayControlling {}

public protocol NetworkAvailabilityChecking {
    func isNetworkAvailable() async -> Bool
}

public enum AutoclickTickResult: Equatable {
    case notDueYet
    case queuedNoNetwork(isStart: Bool)
    case alreadyInDesiredState(isStart: Bool)
    case clicked(isStart: Bool)
    case sessionUnavailable
}

public actor AutoclickScheduler {
    public init(client: any WplanDayControlling, network: any NetworkAvailabilityChecking, configuration: ScheduleConfiguration, calendar: Calendar = .current)
    public func updateConfiguration(_ configuration: ScheduleConfiguration)
    public func tick(now: Date) async -> AutoclickTickResult
    public func performManualClick(isStart: Bool, now: Date) async throws
}
```

---

### Task 1: `WplanDayControlling` protocol + fake

**Files:**
- Create: `WplanCore/Sources/WplanCore/Scheduling/WplanDayControlling.swift`
- Create: `WplanCore/Tests/WplanCoreTests/Scheduling/Fakes/FakeWplanDayController.swift`
- Test: `WplanCore/Tests/WplanCoreTests/Scheduling/Fakes/FakeWplanDayControllerTests.swift`

**Interfaces:**
- Consumes: `WplanClient`, `WplanButtonState` (from the prior plan).
- Produces: `WplanDayControlling` protocol + `WplanClient: WplanDayControlling` conformance, and `FakeWplanDayController` — consumed by every scheduler test in this plan (Task 5, 6).

- [x] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/Scheduling/Fakes/FakeWplanDayControllerTests.swift
import XCTest
@testable import WplanCore

final class FakeWplanDayControllerTests: XCTestCase {
    func test_fetchButtonState_returnsConfiguredState() async throws {
        let fake = FakeWplanDayController()
        fake.buttonState = WplanButtonState(isVisible: true, isStart: false)

        let state = try await fake.fetchButtonState()

        XCTAssertEqual(state, WplanButtonState(isVisible: true, isStart: false))
    }

    func test_startOrFinishDay_recordsCalls() async throws {
        let fake = FakeWplanDayController()

        try await fake.startOrFinishDay(isStart: true)

        XCTAssertEqual(fake.startOrFinishDayCalls, [true])
    }

    func test_fetchButtonState_throwsConfiguredError() async {
        let fake = FakeWplanDayController()
        struct Boom: Error {}
        fake.fetchButtonStateError = Boom()

        do {
            _ = try await fake.fetchButtonState()
            XCTFail("expected error")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter FakeWplanDayControllerTests`
Expected: FAIL — `WplanDayControlling`/`FakeWplanDayController` not defined.

- [x] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/Scheduling/WplanDayControlling.swift
public protocol WplanDayControlling {
    func fetchButtonState() async throws -> WplanButtonState
    func startOrFinishDay(isStart: Bool) async throws
}

extension WplanClient: WplanDayControlling {}
```

```swift
// WplanCore/Tests/WplanCoreTests/Scheduling/Fakes/FakeWplanDayController.swift
import WplanCore

final class FakeWplanDayController: WplanDayControlling, @unchecked Sendable {
    var buttonState = WplanButtonState(isVisible: true, isStart: true)
    var fetchButtonStateError: Error?
    var startOrFinishDayError: Error?
    var startOrFinishDayCalls: [Bool] = []

    func fetchButtonState() async throws -> WplanButtonState {
        if let fetchButtonStateError { throw fetchButtonStateError }
        return buttonState
    }

    func startOrFinishDay(isStart: Bool) async throws {
        if let startOrFinishDayError { throw startOrFinishDayError }
        startOrFinishDayCalls.append(isStart)
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter FakeWplanDayControllerTests`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/Scheduling/WplanDayControlling.swift WplanCore/Tests/WplanCoreTests/Scheduling/Fakes/FakeWplanDayController.swift WplanCore/Tests/WplanCoreTests/Scheduling/Fakes/FakeWplanDayControllerTests.swift
git commit -m "feat: add WplanDayControlling protocol and test fake"
```

---

### Task 2: `ClockTime`

**Files:**
- Create: `WplanCore/Sources/WplanCore/Scheduling/ClockTime.swift`
- Test: `WplanCore/Tests/WplanCoreTests/Scheduling/ClockTimeTests.swift`

**Interfaces:**
- Produces: `ClockTime(hour:minute:)`, `ClockTime.date(onDayOf:calendar:) -> Date?` — consumed by `AutoclickScheduler` (Task 5) to turn "09:00" into an actual `Date` to compare against `now`.

- [x] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/Scheduling/ClockTimeTests.swift
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
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter ClockTimeTests`
Expected: FAIL — `ClockTime` not defined.

- [x] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/Scheduling/ClockTime.swift
import Foundation

public struct ClockTime: Equatable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// The `Date` for this hour:minute on the same calendar day as `reference`.
    public func date(onDayOf reference: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reference)
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter ClockTimeTests`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/Scheduling/ClockTime.swift WplanCore/Tests/WplanCoreTests/Scheduling/ClockTimeTests.swift
git commit -m "feat: add ClockTime"
```

---

### Task 3: `ScheduleConfiguration`

**Files:**
- Create: `WplanCore/Sources/WplanCore/Scheduling/ScheduleConfiguration.swift`
- Test: `WplanCore/Tests/WplanCoreTests/Scheduling/ScheduleConfigurationTests.swift`

**Interfaces:**
- Consumes: `ClockTime` (Task 2).
- Produces: `ScheduleConfiguration` — consumed by `AutoclickScheduler` (Task 5) and, later, the Settings-window view model.

- [x] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/Scheduling/ScheduleConfigurationTests.swift
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
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter ScheduleConfigurationTests`
Expected: FAIL — `ScheduleConfiguration` not defined.

- [x] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/Scheduling/ScheduleConfiguration.swift
public struct ScheduleConfiguration: Equatable {
    public var autoStartEnabled: Bool
    public var autoFinishEnabled: Bool
    public var startTime: ClockTime
    public var endTime: ClockTime
    public var autoCalculateEightHours: Bool
    /// `Calendar.component(.weekday, from:)` values: 1 = Sunday ... 7 = Saturday.
    public var activeWeekdays: Set<Int>

    public init(
        autoStartEnabled: Bool,
        autoFinishEnabled: Bool,
        startTime: ClockTime,
        endTime: ClockTime,
        autoCalculateEightHours: Bool,
        activeWeekdays: Set<Int>
    ) {
        self.autoStartEnabled = autoStartEnabled
        self.autoFinishEnabled = autoFinishEnabled
        self.startTime = startTime
        self.endTime = endTime
        self.autoCalculateEightHours = autoCalculateEightHours
        self.activeWeekdays = activeWeekdays
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter ScheduleConfigurationTests`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/Scheduling/ScheduleConfiguration.swift WplanCore/Tests/WplanCoreTests/Scheduling/ScheduleConfigurationTests.swift
git commit -m "feat: add ScheduleConfiguration"
```

---

### Task 4: `NetworkAvailabilityChecking` protocol + fake

**Files:**
- Create: `WplanCore/Sources/WplanCore/Scheduling/NetworkAvailabilityChecking.swift`
- Create: `WplanCore/Tests/WplanCoreTests/Scheduling/Fakes/FakeNetworkAvailability.swift`

No dedicated test for this task — it is a one-method protocol plus a trivial fake; it is exercised through `AutoclickSchedulerTests` in Task 5/6. Still commit it as its own step since it is a distinct, independently reusable interface (the VPN-detection plan implements it directly).

- [x] **Step 1: Write the implementation directly (no separate test — trivial protocol + fake, exercised by Task 5/6)**

```swift
// WplanCore/Sources/WplanCore/Scheduling/NetworkAvailabilityChecking.swift
public protocol NetworkAvailabilityChecking {
    func isNetworkAvailable() async -> Bool
}
```

```swift
// WplanCore/Tests/WplanCoreTests/Scheduling/Fakes/FakeNetworkAvailability.swift
import WplanCore

final class FakeNetworkAvailability: NetworkAvailabilityChecking, @unchecked Sendable {
    var isAvailable = true

    func isNetworkAvailable() async -> Bool { isAvailable }
}
```

- [x] **Step 2: Confirm it compiles**

Run: `cd WplanCore && swift build`
Expected: builds cleanly (no test to run yet — nothing references these types until Task 5).

- [x] **Step 3: Commit**

```bash
git add WplanCore/Sources/WplanCore/Scheduling/NetworkAvailabilityChecking.swift WplanCore/Tests/WplanCoreTests/Scheduling/Fakes/FakeNetworkAvailability.swift
git commit -m "feat: add NetworkAvailabilityChecking protocol and test fake"
```

---

### Task 5: `DayState`

**Files:**
- Create: `WplanCore/Sources/WplanCore/Scheduling/DayState.swift`
- Test: `WplanCore/Tests/WplanCoreTests/Scheduling/DayStateTests.swift`

**Interfaces:**
- Produces: `DayState` (mutable value type: `startHandledManually`, `finishHandledManually`, `startPerformedAt`, `resetIfNewDay(now:calendar:)`, `markStartHandled(at:)`, `markFinishHandled()`) — consumed by `AutoclickScheduler` (Task 6).

- [x] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/Scheduling/DayStateTests.swift
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
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter DayStateTests`
Expected: FAIL — `DayState` not defined.

- [x] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/Scheduling/DayState.swift
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
    /// manual override — added while implementing Task 6, once its tests showed the
    /// automatic path must not set `startHandledManually` (see Task 6 Step 3 notes).
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
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter DayStateTests`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/Scheduling/DayState.swift WplanCore/Tests/WplanCoreTests/Scheduling/DayStateTests.swift
git commit -m "feat: add DayState for per-calendar-day autoclick bookkeeping"
```

---

### Task 6: `AutoclickScheduler.tick()`

**Files:**
- Create: `WplanCore/Sources/WplanCore/Scheduling/AutoclickScheduler.swift`
- Test: `WplanCore/Tests/WplanCoreTests/Scheduling/AutoclickSchedulerTests.swift`

**Interfaces:**
- Consumes: `WplanDayControlling` (Task 1), `ClockTime`/`ScheduleConfiguration` (Task 2/3), `NetworkAvailabilityChecking` (Task 4), `DayState` (Task 5).
- Produces: `AutoclickTickResult`, `AutoclickScheduler.tick(now:) async -> AutoclickTickResult` — consumed by the later timer-driver plan and by tests here.

- [x] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/Scheduling/AutoclickSchedulerTests.swift
import XCTest
@testable import WplanCore

final class AutoclickSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // Wednesday 2026-09-02
    private func time(hour: Int, minute: Int = 0, day: Int = 2) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    private func makeConfiguration(autoStart: Bool = true, autoFinish: Bool = true) -> ScheduleConfiguration {
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
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter AutoclickSchedulerTests`
Expected: FAIL — `AutoclickScheduler`/`AutoclickTickResult` not defined.

- [x] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/Scheduling/AutoclickScheduler.swift
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

        // Evaluate start first; only short-circuit on a result worth reporting alone
        // (an actual click, a queued click, or a session problem). "Already done" or
        // "not due" must fall through so a due finish click in the same tick still runs.
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
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter AutoclickSchedulerTests`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/Scheduling/AutoclickScheduler.swift WplanCore/Tests/WplanCoreTests/Scheduling/AutoclickSchedulerTests.swift
git commit -m "feat: add AutoclickScheduler.tick() decision engine"
```

---

### Task 7: `AutoclickScheduler.performManualClick()` — cancels today's automatic click

**Files:**
- Modify: `WplanCore/Tests/WplanCoreTests/Scheduling/AutoclickSchedulerTests.swift`

**Interfaces:**
- `performManualClick(isStart:now:)` already implemented in Task 6 — this task adds the tests proving it (a) clicks immediately regardless of scheduled time, and (b) suppresses the automatic click for the rest of the day.

- [x] **Step 1: Write the failing test**

```swift
// append to WplanCore/Tests/WplanCoreTests/Scheduling/AutoclickSchedulerTests.swift
extension AutoclickSchedulerTests {
    func test_performManualClick_clicksImmediatelyBeforeScheduledTime() async throws {
        let client = FakeWplanDayController()
        let network = FakeNetworkAvailability()
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        try await scheduler.performManualClick(isStart: true, now: try time(hour: 7, minute: 30))

        XCTAssertEqual(client.startOrFinishDayCalls, [true])
    }

    func test_performManualClick_suppressesAutomaticClickForRestOfDay() async throws {
        let client = FakeWplanDayController()
        let network = FakeNetworkAvailability()
        let scheduler = AutoclickScheduler(client: client, network: network, configuration: makeConfiguration(), calendar: calendar)

        try await scheduler.performManualClick(isStart: true, now: try time(hour: 7, minute: 30))
        let laterTick = await scheduler.tick(now: try time(hour: 9, minute: 0))

        XCTAssertEqual(laterTick, .notDueYet)
        XCTAssertEqual(client.startOrFinishDayCalls, [true]) // only the manual click, no automatic one
    }
}
```

- [x] **Step 2: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter AutoclickSchedulerTests`
Expected: PASS (all `AutoclickSchedulerTests`, including the two new ones). `performManualClick` was already implemented in Task 6, so this task only adds coverage — if either new test fails, the bug is in that method's `dayState.markStartHandled`/`markFinishHandled` calls; fix there, not here.

- [x] **Step 3: Commit**

```bash
git add WplanCore/Tests/WplanCoreTests/Scheduling/AutoclickSchedulerTests.swift
git commit -m "test: cover AutoclickScheduler.performManualClick() overriding the schedule"
```

---

## Roadmap after this plan

1. **VPN Detection Service** — implements `NetworkAvailabilityChecking` for real (network interface/route + ping), used to construct the production `AutoclickScheduler`.
2. **Timer driver + App shell** — Xcode project, App Group, something calling `scheduler.tick(now: Date())` on an interval and wiring `WplanSessionFactory`/`KeychainStore` together into one running background agent.
3. **WidgetKit extension** — the "ring" view (design doc screen `1a`), reading state written by the timer driver via shared storage.
4. **Menu bar app + popover, Settings, login window, diagnostics, notifications** — as previously planned.
