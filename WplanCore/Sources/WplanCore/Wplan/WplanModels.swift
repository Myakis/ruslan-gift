import Foundation

public struct WplanButtonState: Decodable, Equatable {
    public let isVisible: Bool
    public let isStart: Bool

    public init(isVisible: Bool, isStart: Bool) {
        self.isVisible = isVisible
        self.isStart = isStart
    }
}

public struct WplanCredentials: Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

struct StartOrFinishButtonStateData: Decodable {
    let startOrFinishDayButtonState: WplanButtonState
}
