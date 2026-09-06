import Foundation

/// The small slice of day status the host app writes to the shared App Group
/// container and the widget extension reads back — this is the only channel
/// between the two processes, since a widget extension can't call WplanClient
/// on its own schedule cheaply. No real worked-hours field: the Wplan API has no
/// endpoint that returns one (see WplanCore's foundation plan's Known Limitation).
/// `startedAt`/`scheduledFinishAt` let the widget draw a progress ring anyway,
/// computed locally from when *this app* recorded the start click plus the
/// configured schedule — not a server-verified duration.
public struct WidgetSnapshot: Codable, Equatable {
    /// `nil` when we've never once successfully read the day status (e.g. VPN has
    /// never connected since install) — as opposed to `vpnStatus`, which is always
    /// known since it doesn't require reaching Wplan.
    public let isStart: Bool?
    public let vpnStatus: VPNNetworkChecker.Status
    /// When today's start click happened, if this app instance recorded it (see
    /// `AutoclickScheduler.currentStartedAt()`'s doc comment for the caveat).
    public let startedAt: Date?
    /// The scheduled finish instant used to compute the ring's fill fraction.
    public let scheduledFinishAt: Date?
    /// When today's day was finished, if this app instance recorded it — the only
    /// way to tell "day finished" apart from "day never started" apart, since the
    /// Wplan API's own button state can't (see `DayState.autoStartSuppressedToday`).
    public let finishedAt: Date?
    /// True when today's weekday isn't in `ScheduleConfiguration.activeWeekdays`
    /// — the widget shows a plain "day off" state and skips the VPN check
    /// entirely rather than reporting on a day the schedule doesn't cover.
    public let isRestDay: Bool
    public let updatedAt: Date

    public init(isStart: Bool?, vpnStatus: VPNNetworkChecker.Status, startedAt: Date?, scheduledFinishAt: Date?, finishedAt: Date?, isRestDay: Bool = false, updatedAt: Date) {
        self.isStart = isStart
        self.vpnStatus = vpnStatus
        self.startedAt = startedAt
        self.scheduledFinishAt = scheduledFinishAt
        self.finishedAt = finishedAt
        self.isRestDay = isRestDay
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case isStart, vpnStatus, startedAt, scheduledFinishAt, finishedAt, isRestDay, updatedAt
    }

    /// Custom decode so a snapshot written before `isRestDay` existed (no such
    /// key in the persisted JSON) still decodes, instead of the widget falling
    /// back to a stale/missing snapshot until the next write.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isStart = try container.decodeIfPresent(Bool.self, forKey: .isStart)
        vpnStatus = try container.decode(VPNNetworkChecker.Status.self, forKey: .vpnStatus)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        scheduledFinishAt = try container.decodeIfPresent(Date.self, forKey: .scheduledFinishAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        isRestDay = try container.decodeIfPresent(Bool.self, forKey: .isRestDay) ?? false
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

/// Lets the widget extension (a separate process with no access to the host
/// app's live `AutoclickScheduler` actor) ask the host app to reset today's day
/// state — the extension can only leave a note in the shared App Group
/// UserDefaults; the host app's own loop is the one that actually applies it,
/// since that's the only place the scheduler's real state lives.
public enum WidgetResetRequestStore {
    private static let key = "widgetResetDayRequestedAt"

    public static func requestReset(appGroupIdentifier: String) {
        UserDefaults(suiteName: appGroupIdentifier)?.set(Date(), forKey: key)
    }

    public static func pendingRequestAt(appGroupIdentifier: String) -> Date? {
        UserDefaults(suiteName: appGroupIdentifier)?.object(forKey: key) as? Date
    }

    public static func clearRequest(appGroupIdentifier: String) {
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: key)
    }
}

public enum WidgetSnapshotStore {
    private static let key = "widgetSnapshot"

    public static func save(_ snapshot: WidgetSnapshot, appGroupIdentifier: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func load(appGroupIdentifier: String) -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
