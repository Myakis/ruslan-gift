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
