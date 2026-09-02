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
