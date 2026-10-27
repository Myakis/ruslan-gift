import Foundation

/// Fetches fresh persisted-query hashes when the server stops recognizing ours.
/// Returns `true` if at least one stored hash changed (i.e. a retry can help).
public protocol PersistedQueryHashRefreshing: AnyObject {
    func refreshHashes() async -> Bool
}

public final class ReauthenticatingWplanClient: WplanDayControlling {
    private let client: WplanClient
    private let credentialsStore: KeychainStore
    private weak var hashRefresher: PersistedQueryHashRefreshing?

    public init(client: WplanClient, credentialsStore: KeychainStore, hashRefresher: PersistedQueryHashRefreshing? = nil) {
        self.client = client
        self.credentialsStore = credentialsStore
        self.hashRefresher = hashRefresher
    }

    public func fetchButtonState() async throws -> WplanButtonState {
        try await withHashRecovery { try await self.withReauth { try await self.client.fetchButtonState() } }
    }

    public func startOrFinishDay(isStart: Bool) async throws {
        try await withHashRecovery { try await self.withReauth { try await self.client.startOrFinishDay(isStart: isStart) } }
    }

    public func fetchWorkTimeEvents(for date: Date) async throws -> [WplanWorkTimeEvent] {
        try await withHashRecovery { try await self.withReauth { try await self.client.fetchWorkTimeEvents(for: date) } }
    }

    public func login(username: String, password: String) async throws {
        try await withHashRecovery { try await self.client.login(username: username, password: password) }
    }

    private func withReauth<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as GraphQLClient.ClientError where error.indicatesExpiredSession {
            guard let credentials = try? credentialsStore.load() else { throw error }
            try await client.login(username: credentials.username, password: credentials.password)
            return try await operation()
        }
    }

    private func withHashRecovery<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as GraphQLClient.ClientError where error.isPersistedQueryNotFound {
            guard let hashRefresher, await hashRefresher.refreshHashes() else { throw error }
            return try await operation()
        }
    }
}

extension GraphQLClient.ClientError {
    var indicatesExpiredSession: Bool {
        guard case .graphQL(let messages) = self else { return false }
        return messages.contains { message in
            let upper = message.uppercased()
            return upper.contains("INVALID_TOKEN") || upper.contains("UNAUTHENTICATED") || upper.contains("UNAUTHORIZED")
        }
    }
}
