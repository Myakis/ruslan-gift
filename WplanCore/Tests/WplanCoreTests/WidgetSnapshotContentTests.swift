import XCTest
@testable import WplanCore

final class WidgetSnapshotContentTests: XCTestCase {
    private func snapshot(finishAt: Date?, updatedAt: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            isStart: false,
            vpnStatus: .connected,
            startedAt: Date(timeIntervalSince1970: 1_000),
            scheduledFinishAt: finishAt,
            finishedAt: nil,
            updatedAt: updatedAt
        )
    }

    func test_hasSameContent_ignoresUpdatedAt() {
        let finish = Date(timeIntervalSince1970: 30_000)
        XCTAssertTrue(snapshot(finishAt: finish, updatedAt: Date(timeIntervalSince1970: 1))
            .hasSameContent(as: snapshot(finishAt: finish, updatedAt: Date(timeIntervalSince1970: 2))))
    }

    func test_hasSameContent_detectsScheduleChange() {
        let now = Date()
        XCTAssertFalse(snapshot(finishAt: Date(timeIntervalSince1970: 30_000), updatedAt: now)
            .hasSameContent(as: snapshot(finishAt: Date(timeIntervalSince1970: 29_000), updatedAt: now)))
    }

    func test_hasSameContent_falseWithoutPrevious() {
        XCTAssertFalse(snapshot(finishAt: nil, updatedAt: Date()).hasSameContent(as: nil))
    }
}
