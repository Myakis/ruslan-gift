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

    func test_login_postsCredentialsAndSucceedsWhenNoErrorsArray() async throws {
        var capturedBody: [String: Any]?
        URLProtocolStub.handler = { request in
            capturedBody = try JSONSerialization.jsonObject(with: WplanClientTests.bodyData(from: request)!) as? [String: Any]
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
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_startOrFinishDay_postsIsStartVariable() async throws {
        var capturedBody: [String: Any]?
        URLProtocolStub.handler = { request in
            capturedBody = try JSONSerialization.jsonObject(with: WplanClientTests.bodyData(from: request)!) as? [String: Any]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":null}"#.utf8))
        }
        let client = WplanClient(session: URLProtocolStub.makeStubbedSession())

        try await client.startOrFinishDay(isStart: true)

        let body = try XCTUnwrap(capturedBody)
        XCTAssertEqual(body["operationName"] as? String, "StartOrFinishDay")
        XCTAssertEqual((body["variables"] as! [String: Any])["isStart"] as? Bool, true)
    }

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
}
