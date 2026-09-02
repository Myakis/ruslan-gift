import XCTest
@testable import WplanCore

final class GraphQLClientTests: XCTestCase {
    /// URLSession delivers a POST body to URLProtocol subclasses as `httpBodyStream`,
    /// not `httpBody` (even though the original `URLRequest` was built with `httpBody`).
    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

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
        let body = try XCTUnwrap(GraphQLClientTests.bodyData(from: request))
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
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
