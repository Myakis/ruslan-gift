import XCTest
@testable import WplanCore

final class WplanSessionFactoryTests: XCTestCase {
    func test_withoutAppGroup_usesDefaultCookieStorageAndAcceptsAllCookies() {
        let session = WplanSessionFactory.makeSession(appGroupIdentifier: nil)
        XCTAssertEqual(session.configuration.httpCookieAcceptPolicy, .always)
        XCTAssertTrue(session.configuration.httpShouldSetCookies)
    }
}
