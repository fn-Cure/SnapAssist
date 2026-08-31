import CoreGraphics
import XCTest
@testable import SnapAssistCore

final class MutationLedgerTests: XCTestCase {
    func testConsumesOnlyMatchingExpectedMutation() {
        var ledger = WindowMutationLedger()
        let expected = CGRect(x: 0, y: 0, width: 600, height: 800)
        let operationID = UUID()
        ledger.register(
            operationID: operationID,
            windowID: "window",
            expectedFrame: expected,
            tolerance: 4,
            expiresAt: 11
        )

        XCTAssertEqual(
            ledger.classify(windowID: "window", actualFrame: expected.offsetBy(dx: 2, dy: 0), at: 10),
            .programmatic(operationID: operationID)
        )
        XCTAssertEqual(
            ledger.classify(windowID: "window", actualFrame: expected, at: 10.1),
            .user
        )
    }

    func testGenuineUserMoveIsNotSuppressedDuringPendingMutation() {
        var ledger = WindowMutationLedger()
        ledger.register(
            operationID: UUID(),
            windowID: "window",
            expectedFrame: CGRect(x: 0, y: 0, width: 600, height: 800),
            tolerance: 4,
            expiresAt: 11
        )

        XCTAssertEqual(
            ledger.classify(
                windowID: "window",
                actualFrame: CGRect(x: 200, y: 100, width: 700, height: 500),
                at: 10
            ),
            .user
        )
    }

    func testExpiredMutationDoesNotSuppressDelayedEvent() {
        var ledger = WindowMutationLedger()
        let expected = CGRect(x: 0, y: 0, width: 600, height: 800)
        ledger.register(
            operationID: UUID(),
            windowID: "window",
            expectedFrame: expected,
            tolerance: 4,
            expiresAt: 10.5
        )

        XCTAssertEqual(
            ledger.classify(windowID: "window", actualFrame: expected, at: 10.6),
            .user
        )
    }
}
