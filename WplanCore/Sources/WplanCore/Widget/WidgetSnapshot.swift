import Foundation

/// The small slice of day status the host app writes to the shared App Group
/// container and the widget extension reads back — this is the only channel
/// between the two processes, since a widget extension can't call WplanClient
/// on its own schedule cheaply. No worked-hours field yet: the Wplan API has no
/// endpoint that returns it (see WplanCore's foundation plan's Known Limitation).
public struct WidgetSnapshot: Codable, Equatable {
    public let isStart: Bool
    public let updatedAt: Date

    public init(isStart: Bool, updatedAt: Date) {
        self.isStart = isStart
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
