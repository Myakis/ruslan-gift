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
