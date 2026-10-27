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

/// One worked interval from `WorkTimeEventsForDate`. `endTime` is the current
/// moment while the interval is still running.
public struct WplanWorkTimeEvent: Equatable {
    public let startTime: Date
    public let endTime: Date?

    public init(startTime: Date, endTime: Date?) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct WorkTimeEventsForDateData: Decodable {
    struct RawEvent: Decodable {
        let startTime: String?
        let endTime: String?
    }

    let workTimeEventsForDate: [RawEvent]

    func events(calendar: Calendar) -> [WplanWorkTimeEvent] {
        workTimeEventsForDate.compactMap { raw in
            guard let start = raw.startTime.flatMap({ WplanDateFormat.parseLocalDateTime($0, calendar: calendar) }) else { return nil }
            return WplanWorkTimeEvent(startTime: start, endTime: raw.endTime.flatMap { WplanDateFormat.parseLocalDateTime($0, calendar: calendar) })
        }
    }
}

struct WorkTimeEventsVariables: Encodable {
    let date: String
}

/// Wplan sends wall-clock times without a zone ("2026-10-27T08:51:48", sometimes
/// with 7-digit fractions) — they're the office's local time, same as the Mac's.
enum WplanDateFormat {
    static func parseLocalDateTime(_ string: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: String(string.prefix(19)))
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct LoginVariables: Encodable {
    let username: String
    let password: String
    let accessToken2Fa = ""
    let twoFactorCode = ""
    let code = ""
    let redirectUri = ""
    let source = 1
}

struct StartOrFinishDayVariables: Encodable {
    let isStart: Bool
}
