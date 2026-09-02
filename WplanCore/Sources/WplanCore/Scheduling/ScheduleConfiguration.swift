public struct ScheduleConfiguration: Equatable, Codable {
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
