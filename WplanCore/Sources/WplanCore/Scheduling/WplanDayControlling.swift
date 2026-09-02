public protocol WplanDayControlling {
    func fetchButtonState() async throws -> WplanButtonState
    func startOrFinishDay(isStart: Bool) async throws
}

extension WplanClient: WplanDayControlling {}
