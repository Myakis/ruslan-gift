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
