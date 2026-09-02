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
