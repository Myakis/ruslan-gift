import Foundation

/// Wraps a `WplanClient` so a session that's silently expired (the Wplan API
/// returns a GraphQL "INVALID_TOKEN"-style error instead of a clean 401) gets
/// one automatic re-login attempt from the Keychain-stored credentials before
/// giving up — this is what lets the menu-bar agent keep working across many
/// days of uptime without the user ever noticing the cookie expired.
public final class ReauthenticatingWplanClient: WplanDayControlling {
    private let client: WplanClient
    private let credentialsStore: KeychainStore

    public init(client: WplanClient, credentialsStore: KeychainStore) {
        self.client = client
        self.credentialsStore = credentialsStore
    }

    public func fetchButtonState() async throws -> WplanButtonState {
        try await withReauth { try await client.fetchButtonState() }
    }

    public func startOrFinishDay(isStart: Bool) async throws {
        try await withReauth { try await client.startOrFinishDay(isStart: isStart) }
    }

    /// Retries the operation exactly once, and only after a successful
    /// re-login — never loops, so a genuinely stale/wrong saved password
    /// fails fast instead of retrying forever.
    private func withReauth<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as GraphQLClient.ClientError where error.indicatesExpiredSession {
            guard let credentials = try? credentialsStore.load() else { throw error }
            try await client.login(username: credentials.username, password: credentials.password)
            return try await operation()
        }
    }
}

extension GraphQLClient.ClientError {
    /// The Wplan API reports an expired/invalid session as a normal GraphQL
    /// error (message text, not a distinct HTTP status), so this is a text
    /// match rather than a typed error code.
    var indicatesExpiredSession: Bool {
        guard case .graphQL(let messages) = self else { return false }
        return messages.contains { message in
            let upper = message.uppercased()
            return upper.contains("INVALID_TOKEN") || upper.contains("UNAUTHENTICATED") || upper.contains("UNAUTHORIZED")
        }
    }
}
