import CoreGraphics
import XCTest
@testable import SnapAssistCore

final class FrameReadbackVerifierTests: XCTestCase {
    private let requested = CGRect(x: 600, y: 0, width: 600, height: 800)

    func testDelayedApplicationCanReachRequestedFrameBeforeDeadline() {
        var verifier = FrameReadbackVerifier(requestedFrame: requested, tolerance: 4, maximumSamples: 5)

        XCTAssertEqual(verifier.observe(CGRect(x: 0, y: 0, width: 600, height: 800)), .pending)
        XCTAssertEqual(verifier.observe(CGRect(x: 0, y: 0, width: 600, height: 800)), .pending)
        XCTAssertEqual(verifier.observe(requested.offsetBy(dx: -2, dy: 0)), .verified(requested.offsetBy(dx: -2, dy: 0)))
    }

    func testPersistentPartialMutationReportsMismatchOnlyAtDeadline() {
        var verifier = FrameReadbackVerifier(requestedFrame: requested, tolerance: 4, maximumSamples: 3)
        let sizeOnly = CGRect(x: 0, y: 0, width: 600, height: 800)

        XCTAssertEqual(verifier.observe(sizeOnly), .pending)
        XCTAssertEqual(verifier.observe(sizeOnly), .pending)
        XCTAssertEqual(verifier.observe(sizeOnly), .mismatched(sizeOnly))
    }

    func testMissingReadbackFailsAtDeadline() {
        var verifier = FrameReadbackVerifier(requestedFrame: requested, tolerance: 4, maximumSamples: 2)

        XCTAssertEqual(verifier.observe(nil), .pending)
        XCTAssertEqual(verifier.observe(nil), .unavailable)
    }
}
