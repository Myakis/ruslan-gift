import XCTest
@testable import WplanCore

final class PersistedQueryHashStoreTests: XCTestCase {
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PersistedQueryHashStoreTests.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func test_hash_fallsBackToDefaultsUntilUpdated() {
        let store = PersistedQueryHashStore(appGroupIdentifier: suiteName)
        XCTAssertEqual(store.hash(for: .login), PersistedQueryHashStore.defaultHashes[.login])

        let newHash = String(repeating: "a", count: 64)
        XCTAssertTrue(store.update(newHash, for: .login))
        XCTAssertFalse(store.update(newHash, for: .login))
        XCTAssertEqual(PersistedQueryHashStore(appGroupIdentifier: suiteName).hash(for: .login), newHash)
    }

    func test_update_rejectsMalformedHash() {
        let store = PersistedQueryHashStore(appGroupIdentifier: suiteName)
        XCTAssertFalse(store.update("not-a-hash", for: .buttonState))
        XCTAssertFalse(store.update(String(repeating: "z", count: 64), for: .buttonState))
        XCTAssertEqual(store.hash(for: .buttonState), PersistedQueryHashStore.defaultHashes[.buttonState])
    }

    func test_isPersistedQueryNotFound() {
        XCTAssertTrue(GraphQLClient.ClientError.graphQL(messages: ["PersistedQueryNotFound"]).isPersistedQueryNotFound)
        XCTAssertFalse(GraphQLClient.ClientError.graphQL(messages: ["INVALID_TOKEN"]).isPersistedQueryNotFound)
        XCTAssertFalse(GraphQLClient.ClientError.invalidResponse.isPersistedQueryNotFound)
    }

    func test_reauthenticatingClient_retriesWithRefreshedHash() async throws {
        let store = PersistedQueryHashStore(appGroupIdentifier: suiteName)
        let freshHash = String(repeating: "b", count: 64)
        var requestCount = 0
        URLProtocolStub.handler = { request in
            requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = request.url!.absoluteString.contains(freshHash)
                ? #"{"data":{"startOrFinishDayButtonState":{"isVisible":true,"isStart":false}}}"#
                : #"{"errors":[{"message":"PersistedQueryNotFound"}]}"#
            return (response, Data(json.utf8))
        }
        let refresher = StubRefresher { store.update(freshHash, for: .buttonState) }
        let client = ReauthenticatingWplanClient(
            client: WplanClient(session: URLProtocolStub.makeStubbedSession(), hashStore: store),
            credentialsStore: KeychainStore(service: "PersistedQueryHashStoreTests.unused"),
            hashRefresher: refresher
        )

        let state = try await client.fetchButtonState()

        XCTAssertEqual(state, WplanButtonState(isVisible: true, isStart: false))
        XCTAssertEqual(refresher.calls, 1)
        XCTAssertEqual(requestCount, 2)
    }

    func test_reauthenticatingClient_rethrowsWhenRefreshFindsNothing() async {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"errors":[{"message":"PersistedQueryNotFound"}]}"#.utf8))
        }
        let refresher = StubRefresher { false }
        let client = ReauthenticatingWplanClient(
            client: WplanClient(session: URLProtocolStub.makeStubbedSession()),
            credentialsStore: KeychainStore(service: "PersistedQueryHashStoreTests.unused"),
            hashRefresher: refresher
        )

        do {
            _ = try await client.fetchButtonState()
            XCTFail("expected PersistedQueryNotFound")
        } catch let error as GraphQLClient.ClientError {
            XCTAssertTrue(error.isPersistedQueryNotFound)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(refresher.calls, 1)
    }
}

private final class StubRefresher: PersistedQueryHashRefreshing {
    private let onRefresh: () -> Bool
    private(set) var calls = 0

    init(onRefresh: @escaping () -> Bool) {
        self.onRefresh = onRefresh
    }

    func refreshHashes() async -> Bool {
        calls += 1
        return onRefresh()
    }
}
