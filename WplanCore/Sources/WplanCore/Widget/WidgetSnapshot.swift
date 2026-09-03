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
    public let updatedAt: Date

    public init(isStart: Bool?, vpnStatus: VPNNetworkChecker.Status, startedAt: Date?, scheduledFinishAt: Date?, updatedAt: Date) {
        self.isStart = isStart
        self.vpnStatus = vpnStatus
        self.startedAt = startedAt
        self.scheduledFinishAt = scheduledFinishAt
        self.updatedAt = updatedAt
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
