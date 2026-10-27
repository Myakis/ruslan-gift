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

    func test_fetchWorkTimeEvents_sendsDateAndParsesLocalTimes() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        var capturedURL: URL?
        URLProtocolStub.handler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"data":{"workTimeEventsForDate":[{"startTime":"2026-10-27T08:51:48","endTime":"2026-10-27T09:47:25.0217023","__typename":"EventsForDate"},{"startTime":"2026-10-27T10:00:00","endTime":null}]}}"#
            return (response, Data(json.utf8))
        }
        let client = WplanClient(session: URLProtocolStub.makeStubbedSession())
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!

        let events = try await client.fetchWorkTimeEvents(for: day, calendar: calendar)

        let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(capturedURL), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "operationName" }?.value, "WorkTimeEventsForDate")
        XCTAssertEqual(query.first { $0.name == "variables" }?.value, #"{"date":"2026-10-27"}"#)
        XCTAssertEqual(events, [
            WplanWorkTimeEvent(
                startTime: calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 8, minute: 51, second: 48))!,
                endTime: calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9, minute: 47, second: 25))!
            ),
            WplanWorkTimeEvent(
                startTime: calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 10))!,
                endTime: nil
            )
        ])
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
