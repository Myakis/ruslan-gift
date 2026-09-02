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
