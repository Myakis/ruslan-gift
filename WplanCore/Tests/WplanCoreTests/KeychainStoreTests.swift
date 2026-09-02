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
