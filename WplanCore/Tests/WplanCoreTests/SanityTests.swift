import XCTest
@testable import WplanCore

final class SanityTests: XCTestCase {
    func test_packageBuilds() {
        XCTAssertEqual(WplanCoreVersion.current, "0.1.0")
    }
}
