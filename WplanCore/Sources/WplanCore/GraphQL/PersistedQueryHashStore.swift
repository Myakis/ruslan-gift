import Foundation

/// Current Apollo persisted-query hashes per operation. Wplan's frontend rotates
/// them on redeploy, so they live in the App Group defaults (updated by
/// `WplanQuerySniffer`) with the last known values as a fallback.
public struct PersistedQueryHashStore {
    public enum Operation: String, CaseIterable, Sendable {
        case login = "Login"
        case buttonState = "StartOrFinishButtonState"
        case startOrFinishDay = "StartOrFinishDay"
        case workTimeEvents = "WorkTimeEventsForDate"
    }

    public struct Entry: Equatable, Sendable {
        public let operation: Operation
        public let hash: String
        public let updatedAt: Date?
    }

    static let defaultHashes: [Operation: String] = [
        .login: "9eb6f08a2c0e0088284f62997ac93456f11859433660e3e4b3098b14391b8bef",
        .buttonState: "d8142718a7d030614362030016adf01cf85fb1950b9bd94fbd3d3dd6d27c8d38",
        .startOrFinishDay: "7809b05aa2dcb5ab05e21db5923aafb32a92cddfcaa56626593267775866e3f4",
        .workTimeEvents: "7e11d6958a8547010a4c2160ef6229a3f17a2235bb3b5ca809708d2f374219b0"
    ]

    private let defaults: UserDefaults?

    public init(appGroupIdentifier: String?) {
        defaults = appGroupIdentifier.flatMap { UserDefaults(suiteName: $0) }
    }

    public func hash(for operation: Operation) -> String {
        defaults?.string(forKey: Self.hashKey(operation)) ?? Self.defaultHashes[operation]!
    }

    public func entries() -> [Entry] {
        Operation.allCases.map { operation in
            Entry(
                operation: operation,
                hash: hash(for: operation),
                updatedAt: defaults?.object(forKey: Self.dateKey(operation)) as? Date
            )
        }
    }

    /// Returns `true` if the stored hash actually changed.
    @discardableResult
    public func update(_ hash: String, for operation: Operation, at date: Date = Date()) -> Bool {
        guard Self.isValidHash(hash) else { return false }
        let normalized = hash.lowercased()
        let changed = normalized != self.hash(for: operation)
        defaults?.set(normalized, forKey: Self.hashKey(operation))
        defaults?.set(date, forKey: Self.dateKey(operation))
        return changed
    }

    static func isValidHash(_ hash: String) -> Bool {
        hash.count == 64 && hash.allSatisfy(\.isHexDigit)
    }

    private static func hashKey(_ operation: Operation) -> String { "persistedQueryHash.\(operation.rawValue)" }
    private static func dateKey(_ operation: Operation) -> String { "persistedQueryHashUpdatedAt.\(operation.rawValue)" }
}

extension GraphQLClient.ClientError {
    public var isPersistedQueryNotFound: Bool {
        guard case .graphQL(let messages) = self else { return false }
        return messages.contains { $0.localizedCaseInsensitiveContains("PersistedQueryNotFound") }
    }
}
