import XCTest
@testable import SnapAssistCore

final class PlacementOperationGateTests: XCTestCase {
    func testRejectsSecondPlacementWhileOneIsActive() {
        var gate = PlacementOperationGate()

        XCTAssertNotNil(gate.begin())
        XCTAssertNil(gate.begin())
        XCTAssertTrue(gate.isBusy)
    }

    func testOnlyMatchingOperationCanFinishGate() throws {
        var gate = PlacementOperationGate()
        let active = try XCTUnwrap(gate.begin())

        XCTAssertFalse(gate.finish(UUID()))
        XCTAssertTrue(gate.isBusy)
        XCTAssertTrue(gate.finish(active))
        XCTAssertFalse(gate.isBusy)
    }

    func testCancelReleasesGateForNextPlacement() throws {
        var gate = PlacementOperationGate()
        let cancelled = try XCTUnwrap(gate.begin())

        gate.cancel()
        let replacement = try XCTUnwrap(gate.begin())

        XCTAssertNotEqual(replacement, cancelled)
        XCTAssertFalse(gate.finish(cancelled))
        XCTAssertTrue(gate.finish(replacement))
    }
}
