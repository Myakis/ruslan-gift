# Wplan API Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone, unit-tested Swift package (`WplanCore`) that can log in to Wplan, read the "start/finish day" button state, and click start/finish — over a headless HTTP GraphQL session, with credentials in Keychain. No UI, no WidgetKit, no VPN detection yet — this is the engine everything else (widget, menu bar, autoclick scheduler) will call into.

**Architecture:** A local Swift Package with three layers: (1) a small generic `GraphQLClient` that speaks Wplan's persisted-query GraphQL protocol over `URLSession`, (2) a `WplanClient` that wraps the three known operations (`Login`, `StartOrFinishButtonState`, `StartOrFinishDay`) with typed methods, (3) a `KeychainStore` for credentials. Session state (cookies) rides on `URLSession`'s own cookie storage — for real usage this is backed by an App Group container so app, widget extension, and background scheduler share one session; tests use an isolated in-process stub, never the network.

**Tech Stack:** Swift 5.9+, Swift Package Manager, `XCTest`, Apple `Security` framework (Keychain), `Foundation` (`URLSession`, `HTTPCookieStorage`). No third-party dependencies.

**Spec:** `Функционал приложения IFMO/Time Widget Concepts.dc.html` (product/UX spec) plus the following reverse-engineered API contract, captured live from the browser and supplied by the user in conversation (2026-09-02) — this plan is the first place this contract is written down, so treat the values below as authoritative:

- Base URL: `https://wplan.office.lan/ru-RU/api/graphql`
- All operations are **persisted queries**: the request never carries GraphQL query text, only `operationName`, `variables`, and `extensions.persistedQuery.sha256Hash`. The server already has these hashes registered — the client never needs the actual query source.
- `Login` — POST, hash `fb78036c7e60ac4e484699dc6c4ac71070ff22dbd5328207f22888ba7ff9e608`, variables: `{"username": String, "password": String, "accessToken2Fa": "", "twoFactorCode": "", "code": "", "redirectUri": "", "source": 1}`. Session is conveyed via `Set-Cookie` (`connect.sid1`, `sh.session.id`), not via response body — response body shape on success/failure is **not yet captured**.
- `StartOrFinishButtonState` — GET, hash `d8142718a7d030614362030016adf01cf85fb1950b9bd94fbd3d3dd6d27c8d38`, variables `{}`, query params `operationName`, `variables`, `extensions` (each URL-encoded JSON). Confirmed response: `{"data":{"startOrFinishDayButtonState":{"isVisible":bool,"isStart":bool,"__typename":"StartOrFinishWorkDayButtonState"}}}`. `isStart: true` means the day has **not** started yet (clicking will start it); `isStart: false` means the day is running (clicking will finish it).
- `StartOrFinishDay` — POST, hash `7809b05aa2dcb5ab05e21db5923aafb32a92cddfcaa56626593267775866e3f4`, variables `{"isStart": Bool}`. Response body shape **not yet captured**.
- All three requests are same-origin, `content-type: application/json`, and include an `x-xsrf-token: undefined` header in every captured sample (no XSRF cookie was ever present in the jar) — this appears to be a harmless client-side artifact, not an enforced CSRF check. This plan sends the literal header `x-xsrf-token: undefined` to match observed traffic; revisit if the server starts rejecting requests without a real token.

## Global Constraints

- Credentials live **only** in Keychain — never in plain files, never in `UserDefaults`, never logged.
- No third-party networking library — `URLSession` only (matches the "headless HTTP session" requirement from the spec's technical notes).
- The real session cookie values and the real password captured in this conversation must **never** be written into source, tests, or fixtures — use placeholder values everywhere.
- Every network-touching type must be constructible with an injected `URLSession`, so tests never hit the real network or the real Keychain by accident (Keychain tests use a dedicated, cleaned-up-in-teardown service identifier).

## Known Limitation (carried forward, not solved by this plan)

`Login` and `StartOrFinishDay` response bodies were never captured failing or succeeding in a way that reveals their `data`/`errors` shape beyond the generic GraphQL envelope. This plan treats **HTTP 2xx + no top-level `errors` array** as success for both operations, and a non-empty `errors` array as failure. If Wplan actually signals a wrong password or a rejected click via `data: {..., success: false}` rather than a GraphQL error, this plan's `login`/`startOrFinishDay` will incorrectly report success. Follow-up task (not in this plan): capture one failing-login curl and one already-clicked `StartOrFinishDay` curl, then tighten `WplanClient` accordingly.

---

## File Structure

```
WplanCore/                                   (new Swift package, local to the repo)
├── Package.swift
├── Sources/WplanCore/
│   ├── GraphQL/
│   │   ├── PersistedQuery.swift             — GraphQLOperation<Variables>, PersistedQueryExtensions, EmptyVariables
│   │   └── GraphQLClient.swift              — builds requests, decodes envelope, both execute() and executeIgnoringResult()
│   ├── Wplan/
│   │   ├── WplanModels.swift                — WplanButtonState, WplanCredentials, GraphQLErrorMessage
│   │   └── WplanClient.swift                — login(), fetchButtonState(), startOrFinishDay(isStart:)
│   ├── Session/
│   │   └── WplanSessionFactory.swift        — URLSession builder wired to an App-Group-backed HTTPCookieStorage
│   └── Credentials/
│       └── KeychainStore.swift              — save/load/delete WplanCredentials via Security framework
└── Tests/WplanCoreTests/
    ├── Support/URLProtocolStub.swift        — intercepts requests, returns canned (status, data)
    ├── GraphQLClientTests.swift
    ├── WplanClientTests.swift
    └── KeychainStoreTests.swift
```

## Interfaces produced (for later plans — widget, scheduler, VPN detection — to consume)

```swift
public struct WplanCredentials: Equatable { public let username: String; public let password: String }
public struct WplanButtonState: Decodable, Equatable { public let isVisible: Bool; public let isStart: Bool }

public final class WplanClient {
    public init(baseURL: URL = WplanClient.defaultBaseURL, session: URLSession)
    public func login(username: String, password: String) async throws
    public func fetchButtonState() async throws -> WplanButtonState
    public func startOrFinishDay(isStart: Bool) async throws
}

public enum WplanSessionFactory {
    public static func makeSession(appGroupIdentifier: String?) -> URLSession
}

public struct KeychainStore {
    public init(service: String)
    public func save(_ credentials: WplanCredentials) throws
    public func load() throws -> WplanCredentials?
    public func delete() throws
}
```

---

### Task 1: Package scaffold

**Files:**
- Create: `WplanCore/Package.swift`
- Create: `WplanCore/Sources/WplanCore/WplanCore.swift`
- Create: `WplanCore/Tests/WplanCoreTests/SanityTests.swift`

**Interfaces:**
- Produces: a buildable, testable SPM package target `WplanCore` and test target `WplanCoreTests`.

- [ ] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/SanityTests.swift
import XCTest
@testable import WplanCore

final class SanityTests: XCTestCase {
    func test_packageBuilds() {
        XCTAssertEqual(WplanCoreVersion.current, "0.1.0")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter SanityTests`
Expected: FAIL — `WplanCoreVersion` not defined (compile error).

- [ ] **Step 3: Write minimal implementation**

```swift
// WplanCore/Package.swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WplanCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WplanCore", targets: ["WplanCore"])
    ],
    targets: [
        .target(name: "WplanCore"),
        .testTarget(name: "WplanCoreTests", dependencies: ["WplanCore"])
    ]
)
```

```swift
// WplanCore/Sources/WplanCore/WplanCore.swift
public enum WplanCoreVersion {
    public static let current = "0.1.0"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter SanityTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WplanCore/Package.swift WplanCore/Sources/WplanCore/WplanCore.swift WplanCore/Tests/WplanCoreTests/SanityTests.swift
git commit -m "chore: scaffold WplanCore swift package"
```

---

### Task 2: URLProtocol test stub

**Files:**
- Create: `WplanCore/Tests/WplanCoreTests/Support/URLProtocolStub.swift`

**Interfaces:**
- Produces: `URLProtocolStub` (settable `handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?`) and `URLProtocolStub.makeStubbedSession() -> URLSession`, used by every later networking test in this plan.

- [ ] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/Support/URLProtocolStubTests.swift
import XCTest
@testable import WplanCore

final class URLProtocolStubTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func test_stubReturnsConfiguredResponse() async throws {
        let url = URL(string: "https://wplan.office.lan/ru-RU/api/graphql")!
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"ok":true}"#.utf8))
        }
        let session = URLProtocolStub.makeStubbedSession()
        let (data, response) = try await session.data(from: url)
        let http = response as! HTTPURLResponse
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true}"#)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter URLProtocolStubTests`
Expected: FAIL — `URLProtocolStub` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// WplanCore/Tests/WplanCoreTests/Support/URLProtocolStub.swift
import Foundation

final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter URLProtocolStubTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WplanCore/Tests/WplanCoreTests/Support/URLProtocolStub.swift WplanCore/Tests/WplanCoreTests/Support/URLProtocolStubTests.swift
git commit -m "test: add URLProtocol stub for offline networking tests"
```

---

### Task 3: PersistedQuery + GraphQLOperation model

**Files:**
- Create: `WplanCore/Sources/WplanCore/GraphQL/PersistedQuery.swift`
- Test: `WplanCore/Tests/WplanCoreTests/PersistedQueryTests.swift`

**Interfaces:**
- Produces: `GraphQLOperation<Variables: Encodable>`, `PersistedQueryExtensions`, `EmptyVariables` — consumed by `GraphQLClient` (Task 4) and `WplanClient` (Task 6/7/8).

- [ ] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/PersistedQueryTests.swift
import XCTest
@testable import WplanCore

final class PersistedQueryTests: XCTestCase {
    func test_extensionsEncodeToPersistedQueryShape() throws {
        let extensions = PersistedQueryExtensions(sha256Hash: "abc123")
        let data = try JSONEncoder().encode(extensions)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let persistedQuery = json["persistedQuery"] as! [String: Any]
        XCTAssertEqual(persistedQuery["version"] as? Int, 1)
        XCTAssertEqual(persistedQuery["sha256Hash"] as? String, "abc123")
    }

    func test_emptyVariablesEncodeToEmptyObject() throws {
        let data = try JSONEncoder().encode(EmptyVariables())
        XCTAssertEqual(String(data: data, encoding: .utf8), "{}")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter PersistedQueryTests`
Expected: FAIL — `PersistedQueryExtensions`/`EmptyVariables` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/GraphQL/PersistedQuery.swift
import Foundation

public struct PersistedQueryExtensions: Encodable {
    public struct Inner: Encodable {
        public let version: Int
        public let sha256Hash: String
    }
    public let persistedQuery: Inner

    public init(sha256Hash: String, version: Int = 1) {
        self.persistedQuery = Inner(version: version, sha256Hash: sha256Hash)
    }
}

/// Marker type for operations that take no variables (e.g. `StartOrFinishButtonState`).
public struct EmptyVariables: Encodable {}

public struct GraphQLOperation<Variables: Encodable> {
    public let operationName: String
    public let variables: Variables
    public let sha256Hash: String

    public init(operationName: String, variables: Variables, sha256Hash: String) {
        self.operationName = operationName
        self.variables = variables
        self.sha256Hash = sha256Hash
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter PersistedQueryTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/GraphQL/PersistedQuery.swift WplanCore/Tests/WplanCoreTests/PersistedQueryTests.swift
git commit -m "feat: add persisted-query GraphQL operation model"
```

---

### Task 4: GraphQLClient — request building (GET + POST)

**Files:**
- Create: `WplanCore/Sources/WplanCore/GraphQL/GraphQLClient.swift`
- Test: `WplanCore/Tests/WplanCoreTests/GraphQLClientTests.swift`

**Interfaces:**
- Consumes: `GraphQLOperation<Variables>`, `PersistedQueryExtensions` (Task 3), `URLProtocolStub` (Task 2).
- Produces: `GraphQLClient(baseURL:session:)`, `GraphQLClient.GraphQLHTTPMethod { case get, post }`, `GraphQLClient.ClientError`, `execute<Variables,ResponseData>(_:method:dataType:) async throws -> ResponseData`, `executeIgnoringResult<Variables>(_:method:) async throws -> Void` — consumed by `WplanClient` (Task 6/7/8).

- [ ] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/GraphQLClientTests.swift
import XCTest
@testable import WplanCore

final class GraphQLClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    private let baseURL = URL(string: "https://wplan.office.lan/ru-RU/api/graphql")!

    func test_postRequestBodyMatchesPersistedQueryShape() async throws {
        struct Variables: Encodable { let isStart: Bool }
        var capturedRequest: URLRequest?
        URLProtocolStub.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":{}}"#.utf8))
        }
        let client = GraphQLClient(baseURL: baseURL, session: URLProtocolStub.makeStubbedSession())
        let operation = GraphQLOperation(operationName: "StartOrFinishDay", variables: Variables(isStart: true), sha256Hash: "hash-under-test")

        try await client.executeIgnoringResult(operation, method: .post)

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBodyStreamOrBodyData())
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(json["operationName"] as? String, "StartOrFinishDay")
        XCTAssertEqual((json["variables"] as! [String: Any])["isStart"] as? Bool, true)
        let extensions = json["extensions"] as! [String: Any]
        let persistedQuery = extensions["persistedQuery"] as! [String: Any]
        XCTAssertEqual(persistedQuery["sha256Hash"] as? String, "hash-under-test")
    }

    func test_getRequestEncodesVariablesAndExtensionsAsQueryItems() async throws {
        var capturedRequest: URLRequest?
        URLProtocolStub.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":{}}"#.utf8))
        }
        let client = GraphQLClient(baseURL: baseURL, session: URLProtocolStub.makeStubbedSession())
        let operation = GraphQLOperation(operationName: "StartOrFinishButtonState", variables: EmptyVariables(), sha256Hash: "hash-under-test")

        try await client.executeIgnoringResult(operation, method: .get)

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["operationName"], "StartOrFinishButtonState")
        XCTAssertEqual(items["variables"], "{}")
        XCTAssertTrue(items["extensions"]!.contains("hash-under-test"))
    }

    func test_executeThrowsOnGraphQLErrorsArray() async {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"errors":[{"message":"boom"}]}"#.utf8))
        }
        let client = GraphQLClient(baseURL: baseURL, session: URLProtocolStub.makeStubbedSession())
        let operation = GraphQLOperation(operationName: "X", variables: EmptyVariables(), sha256Hash: "h")

        do {
            try await client.executeIgnoringResult(operation, method: .get)
            XCTFail("expected error")
        } catch GraphQLClient.ClientError.graphQL(let messages) {
            XCTAssertEqual(messages, ["boom"])
        }
    }
}

private extension URLRequest {
    func httpBodyStreamOrBodyData() -> Data? { httpBody }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter GraphQLClientTests`
Expected: FAIL — `GraphQLClient` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/GraphQL/GraphQLClient.swift
import Foundation

public final class GraphQLClient {
    public enum GraphQLHTTPMethod { case get, post }

    public enum ClientError: Error, Equatable {
        case invalidResponse
        case http(status: Int)
        case graphQL(messages: [String])
    }

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession) {
        self.baseURL = baseURL
        self.session = session
    }

    public func execute<Variables: Encodable, ResponseData: Decodable>(
        _ operation: GraphQLOperation<Variables>,
        method: GraphQLHTTPMethod,
        dataType: ResponseData.Type
    ) async throws -> ResponseData {
        let body = try await performRequest(for: operation, method: method)
        let envelope = try JSONDecoder().decode(GraphQLEnvelope<ResponseData>.self, from: body)
        if let errors = envelope.errors, !errors.isEmpty {
            throw ClientError.graphQL(messages: errors.map(\.message))
        }
        guard let data = envelope.data else { throw ClientError.invalidResponse }
        return data
    }

    public func executeIgnoringResult<Variables: Encodable>(
        _ operation: GraphQLOperation<Variables>,
        method: GraphQLHTTPMethod
    ) async throws {
        let body = try await performRequest(for: operation, method: method)
        struct ErrorsOnlyEnvelope: Decodable { let errors: [GraphQLErrorMessage]? }
        let envelope = try JSONDecoder().decode(ErrorsOnlyEnvelope.self, from: body)
        if let errors = envelope.errors, !errors.isEmpty {
            throw ClientError.graphQL(messages: errors.map(\.message))
        }
    }

    private func performRequest<Variables: Encodable>(
        for operation: GraphQLOperation<Variables>,
        method: GraphQLHTTPMethod
    ) async throws -> Data {
        let request = try makeRequest(for: operation, method: method)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.http(status: http.statusCode) }
        return data
    }

    private func makeRequest<Variables: Encodable>(
        for operation: GraphQLOperation<Variables>,
        method: GraphQLHTTPMethod
    ) throws -> URLRequest {
        let extensions = PersistedQueryExtensions(sha256Hash: operation.sha256Hash)
        switch method {
        case .post:
            var request = URLRequest(url: baseURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("undefined", forHTTPHeaderField: "x-xsrf-token")
            let body = GraphQLRequestBody(operationName: operation.operationName, variables: operation.variables, extensions: extensions)
            request.httpBody = try JSONEncoder().encode(body)
            return request
        case .get:
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw ClientError.invalidResponse
            }
            let variablesJSON = String(data: try JSONEncoder().encode(operation.variables), encoding: .utf8) ?? "{}"
            let extensionsJSON = String(data: try JSONEncoder().encode(extensions), encoding: .utf8) ?? "{}"
            components.queryItems = [
                URLQueryItem(name: "operationName", value: operation.operationName),
                URLQueryItem(name: "variables", value: variablesJSON),
                URLQueryItem(name: "extensions", value: extensionsJSON)
            ]
            guard let url = components.url else { throw ClientError.invalidResponse }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("undefined", forHTTPHeaderField: "x-xsrf-token")
            return request
        }
    }
}

private struct GraphQLRequestBody<Variables: Encodable>: Encodable {
    let operationName: String
    let variables: Variables
    let extensions: PersistedQueryExtensions
}

struct GraphQLEnvelope<ResponseData: Decodable>: Decodable {
    let data: ResponseData?
    let errors: [GraphQLErrorMessage]?
}

public struct GraphQLErrorMessage: Decodable, Equatable {
    public let message: String
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter GraphQLClientTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/GraphQL/GraphQLClient.swift WplanCore/Tests/WplanCoreTests/GraphQLClientTests.swift
git commit -m "feat: add GraphQLClient for Wplan's persisted-query protocol"
```

---

### Task 5: WplanSessionFactory — App-Group-backed cookie storage

**Files:**
- Create: `WplanCore/Sources/WplanCore/Session/WplanSessionFactory.swift`
- Test: `WplanCore/Tests/WplanCoreTests/WplanSessionFactoryTests.swift`

**Interfaces:**
- Produces: `WplanSessionFactory.makeSession(appGroupIdentifier: String?) -> URLSession`, used by the app/widget/scheduler targets in later plans (not by tests in this plan, which build their own stubbed sessions directly).

- [ ] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/WplanSessionFactoryTests.swift
import XCTest
@testable import WplanCore

final class WplanSessionFactoryTests: XCTestCase {
    func test_withoutAppGroup_usesDefaultCookieStorageAndAcceptsAllCookies() {
        let session = WplanSessionFactory.makeSession(appGroupIdentifier: nil)
        XCTAssertEqual(session.configuration.httpCookieAcceptPolicy, .always)
        XCTAssertTrue(session.configuration.httpShouldSetCookies)
    }
}
```

Note: the App-Group-backed branch (`HTTPCookieStorage(forGroupContainerIdentifier:)`) is **not** covered by an automated test here — it requires a real App Group container/entitlement that doesn't exist in a bare `swift test` process. Verify it manually once the host app target (a later plan) has the App Group entitlement configured, by confirming the widget extension and host app observe the same cookies after a login.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter WplanSessionFactoryTests`
Expected: FAIL — `WplanSessionFactory` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/Session/WplanSessionFactory.swift
import Foundation

public enum WplanSessionFactory {
    /// - Parameter appGroupIdentifier: pass the app's App Group id (e.g. `"group.ru.itmo.wplanwidget"`)
    ///   so the host app, widget extension, and background scheduler share one cookie jar. Pass `nil`
    ///   in contexts without an App Group (tests, a CLI harness).
    public static func makeSession(appGroupIdentifier: String?) -> URLSession {
        let configuration = URLSessionConfiguration.default
        if let appGroupIdentifier {
            configuration.httpCookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: appGroupIdentifier)
        }
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter WplanSessionFactoryTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/Session/WplanSessionFactory.swift WplanCore/Tests/WplanCoreTests/WplanSessionFactoryTests.swift
git commit -m "feat: add App-Group-aware URLSession factory for shared cookies"
```

---

### Task 6: WplanClient.fetchButtonState()

**Files:**
- Create: `WplanCore/Sources/WplanCore/Wplan/WplanModels.swift`
- Create: `WplanCore/Sources/WplanCore/Wplan/WplanClient.swift`
- Test: `WplanCore/Tests/WplanCoreTests/WplanClientTests.swift`

**Interfaces:**
- Consumes: `GraphQLClient` (Task 4).
- Produces: `WplanButtonState`, `WplanClient(baseURL:session:)`, `WplanClient.fetchButtonState() async throws -> WplanButtonState` — consumed by the autoclick scheduler (later plan) to decide whether a click is still needed and by the widget timeline provider to render the ring.

- [ ] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/WplanClientTests.swift
import XCTest
@testable import WplanCore

final class WplanClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func test_fetchButtonState_decodesConfirmedResponseShape() async throws {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"data":{"startOrFinishDayButtonState":{"isVisible":true,"isStart":true,"__typename":"StartOrFinishWorkDayButtonState"}}}"#
            return (response, Data(json.utf8))
        }
        let client = WplanClient(session: URLProtocolStub.makeStubbedSession())

        let state = try await client.fetchButtonState()

        XCTAssertEqual(state, WplanButtonState(isVisible: true, isStart: true))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter WplanClientTests`
Expected: FAIL — `WplanClient` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/Wplan/WplanModels.swift
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
```

```swift
// WplanCore/Sources/WplanCore/Wplan/WplanClient.swift
import Foundation

public final class WplanClient {
    public static let defaultBaseURL = URL(string: "https://wplan.office.lan/ru-RU/api/graphql")!

    private static let loginHash = "fb78036c7e60ac4e484699dc6c4ac71070ff22dbd5328207f22888ba7ff9e608"
    private static let buttonStateHash = "d8142718a7d030614362030016adf01cf85fb1950b9bd94fbd3d3dd6d27c8d38"
    private static let startOrFinishDayHash = "7809b05aa2dcb5ab05e21db5923aafb32a92cddfcaa56626593267775866e3f4"

    private let graphQL: GraphQLClient

    public init(baseURL: URL = WplanClient.defaultBaseURL, session: URLSession) {
        self.graphQL = GraphQLClient(baseURL: baseURL, session: session)
    }

    public func fetchButtonState() async throws -> WplanButtonState {
        let operation = GraphQLOperation(
            operationName: "StartOrFinishButtonState",
            variables: EmptyVariables(),
            sha256Hash: Self.buttonStateHash
        )
        let data: StartOrFinishButtonStateData = try await graphQL.execute(operation, method: .get, dataType: StartOrFinishButtonStateData.self)
        return data.startOrFinishDayButtonState
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter WplanClientTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/Wplan/WplanModels.swift WplanCore/Sources/WplanCore/Wplan/WplanClient.swift WplanCore/Tests/WplanCoreTests/WplanClientTests.swift
git commit -m "feat: add WplanClient.fetchButtonState()"
```

---

### Task 7: WplanClient.login() and startOrFinishDay()

**Files:**
- Modify: `WplanCore/Sources/WplanCore/Wplan/WplanClient.swift`
- Modify: `WplanCore/Tests/WplanCoreTests/WplanClientTests.swift`

**Interfaces:**
- Produces: `WplanClient.login(username:password:) async throws`, `WplanClient.startOrFinishDay(isStart:) async throws` — consumed by the autoclick scheduler and the login-window view model (later plans).

- [ ] **Step 1: Write the failing test**

```swift
// append to WplanCore/Tests/WplanCoreTests/WplanClientTests.swift
extension WplanClientTests {
    func test_login_postsCredentialsAndSucceedsWhenNoErrorsArray() async throws {
        var capturedBody: [String: Any]?
        URLProtocolStub.handler = { request in
            capturedBody = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":null}"#.utf8))
        }
        let client = WplanClient(session: URLProtocolStub.makeStubbedSession())

        try await client.login(username: "test.user", password: "test-password-not-real")

        let body = try XCTUnwrap(capturedBody)
        XCTAssertEqual(body["operationName"] as? String, "Login")
        let variables = body["variables"] as! [String: Any]
        XCTAssertEqual(variables["username"] as? String, "test.user")
        XCTAssertEqual(variables["password"] as? String, "test-password-not-real")
        XCTAssertEqual(variables["source"] as? Int, 1)
    }

    func test_login_throwsWhenServerReturnsGraphQLErrors() async {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"errors":[{"message":"invalid credentials"}]}"#.utf8))
        }
        let client = WplanClient(session: URLProtocolStub.makeStubbedSession())

        do {
            try await client.login(username: "test.user", password: "wrong")
            XCTFail("expected error")
        } catch GraphQLClient.ClientError.graphQL(let messages) {
            XCTAssertEqual(messages, ["invalid credentials"])
        }
    }

    func test_startOrFinishDay_postsIsStartVariable() async throws {
        var capturedBody: [String: Any]?
        URLProtocolStub.handler = { request in
            capturedBody = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":null}"#.utf8))
        }
        let client = WplanClient(session: URLProtocolStub.makeStubbedSession())

        try await client.startOrFinishDay(isStart: true)

        let body = try XCTUnwrap(capturedBody)
        XCTAssertEqual(body["operationName"] as? String, "StartOrFinishDay")
        XCTAssertEqual((body["variables"] as! [String: Any])["isStart"] as? Bool, true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter WplanClientTests`
Expected: FAIL — `login`/`startOrFinishDay` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// add to WplanCore/Sources/WplanCore/Wplan/WplanClient.swift, inside WplanClient
public func login(username: String, password: String) async throws {
    let operation = GraphQLOperation(
        operationName: "Login",
        variables: LoginVariables(username: username, password: password),
        sha256Hash: Self.loginHash
    )
    try await graphQL.executeIgnoringResult(operation, method: .post)
}

public func startOrFinishDay(isStart: Bool) async throws {
    let operation = GraphQLOperation(
        operationName: "StartOrFinishDay",
        variables: StartOrFinishDayVariables(isStart: isStart),
        sha256Hash: Self.startOrFinishDayHash
    )
    try await graphQL.executeIgnoringResult(operation, method: .post)
}
```

```swift
// add to WplanCore/Sources/WplanCore/Wplan/WplanModels.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter WplanClientTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/Wplan/WplanClient.swift WplanCore/Sources/WplanCore/Wplan/WplanModels.swift WplanCore/Tests/WplanCoreTests/WplanClientTests.swift
git commit -m "feat: add WplanClient.login() and startOrFinishDay()"
```

---

### Task 8: KeychainStore

**Files:**
- Create: `WplanCore/Sources/WplanCore/Credentials/KeychainStore.swift`
- Test: `WplanCore/Tests/WplanCoreTests/KeychainStoreTests.swift`

**Interfaces:**
- Consumes: `WplanCredentials` (Task 6).
- Produces: `KeychainStore(service:)`, `save(_:) throws`, `load() throws -> WplanCredentials?`, `delete() throws` — consumed by the login-window view model and the autoclick scheduler (later plans) to read stored credentials before calling `WplanClient.login`.

- [ ] **Step 1: Write the failing test**

```swift
// WplanCore/Tests/WplanCoreTests/KeychainStoreTests.swift
import XCTest
@testable import WplanCore

final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore(service: "ru.itmo.wplanwidget.tests.\(UUID().uuidString)")

    override func tearDown() {
        try? store.delete()
        super.tearDown()
    }

    func test_saveThenLoad_roundTripsCredentials() throws {
        let credentials = WplanCredentials(username: "test.user", password: "test-password-not-real")

        try store.save(credentials)
        let loaded = try store.load()

        XCTAssertEqual(loaded, credentials)
    }

    func test_load_returnsNilWhenNothingSaved() throws {
        XCTAssertNil(try store.load())
    }

    func test_delete_removesSavedCredentials() throws {
        try store.save(WplanCredentials(username: "test.user", password: "test-password-not-real"))
        try store.delete()
        XCTAssertNil(try store.load())
    }

    func test_saveTwice_overwritesPreviousCredentials() throws {
        try store.save(WplanCredentials(username: "first", password: "first-pass"))
        try store.save(WplanCredentials(username: "second", password: "second-pass"))

        let loaded = try store.load()

        XCTAssertEqual(loaded, WplanCredentials(username: "second", password: "second-pass"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WplanCore && swift test --filter KeychainStoreTests`
Expected: FAIL — `KeychainStore` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// WplanCore/Sources/WplanCore/Credentials/KeychainStore.swift
import Foundation
import Security

public struct KeychainStore {
    public enum StoreError: Error {
        case unexpectedStatus(OSStatus)
        case corruptedData
    }

    private let service: String
    private let account = "wplan-credentials"

    public init(service: String) {
        self.service = service
    }

    public func save(_ credentials: WplanCredentials) throws {
        let payload = try JSONEncoder().encode(CodablePair(username: credentials.username, password: credentials.password))
        try? delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: payload
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
    }

    public func load() throws -> WplanCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw StoreError.corruptedData }
        let pair = try JSONDecoder().decode(CodablePair.self, from: data)
        return WplanCredentials(username: pair.username, password: pair.password)
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }
}

private struct CodablePair: Codable {
    let username: String
    let password: String
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WplanCore && swift test --filter KeychainStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WplanCore/Sources/WplanCore/Credentials/KeychainStore.swift WplanCore/Tests/WplanCoreTests/KeychainStoreTests.swift
git commit -m "feat: add Keychain-backed credential store"
```

---

## Roadmap after this plan (separate plans, not detailed here)

1. **Autoclick Scheduler** — schedule/day-of-week rules, dedupe via `fetchButtonState()`, queueing when offline, using `WplanClient` from this plan.
2. **VPN Detection Service** — network interface/route check + ping, feeds the scheduler's queueing decision.
3. **App shell + WidgetKit extension** — Xcode project, App Group entitlement wiring `WplanSessionFactory`, timeline provider, the "ring" view from design doc screen `1a`.
4. **Menu bar app + popover** — design doc screen `1b`.
5. **Settings, login window, diagnostics window, notifications** — design doc screens `2a`, `2b`, `3b`.

Each of those gets its own plan via this same skill once this foundation is merged and its known limitation (login/click response shape) is either accepted or resolved.
