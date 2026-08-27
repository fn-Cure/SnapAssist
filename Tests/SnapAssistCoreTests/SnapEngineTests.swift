import CoreGraphics
import XCTest
@testable import SnapAssistCore

final class SnapEngineTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testDetectsLeftAndRightHalves() throws {
        let left = try XCTUnwrap(SnapEngine.detect(
            windowFrame: CGRect(x: 0, y: 0, width: 600, height: 800),
            screenFrame: screen
        ))
        let right = try XCTUnwrap(SnapEngine.detect(
            windowFrame: CGRect(x: 600, y: 0, width: 600, height: 800),
            screenFrame: screen
        ))

        XCTAssertEqual(left.layout.kind, .halves)
        XCTAssertEqual(left.coveredZoneIDs, [0])
        XCTAssertEqual(right.layout.kind, .halves)
        XCTAssertEqual(right.coveredZoneIDs, [1])
    }

    func testDetectsSingleAndDoubleThirds() throws {
        let leftThird = try XCTUnwrap(SnapEngine.detect(
            windowFrame: CGRect(x: 0, y: 0, width: 400, height: 800),
            screenFrame: screen
        ))
        let centerThird = try XCTUnwrap(SnapEngine.detect(
            windowFrame: CGRect(x: 400, y: 0, width: 400, height: 800),
            screenFrame: screen
        ))
        let rightTwoThirds = try XCTUnwrap(SnapEngine.detect(
            windowFrame: CGRect(x: 400, y: 0, width: 800, height: 800),
            screenFrame: screen
        ))

        XCTAssertEqual(leftThird.layout.kind, .thirds)
        XCTAssertEqual(leftThird.coveredZoneIDs, [0])
        XCTAssertEqual(centerThird.coveredZoneIDs, [1])
        XCTAssertEqual(rightTwoThirds.coveredZoneIDs, [1, 2])
    }

    func testDetectsEveryCornerQuarter() throws {
        let frames = [
            CGRect(x: 0, y: 400, width: 600, height: 400),
            CGRect(x: 600, y: 400, width: 600, height: 400),
            CGRect(x: 0, y: 0, width: 600, height: 400),
            CGRect(x: 600, y: 0, width: 600, height: 400),
        ]

        for (zoneID, frame) in frames.enumerated() {
            let match = try XCTUnwrap(SnapEngine.detect(windowFrame: frame, screenFrame: screen))
            XCTAssertEqual(match.layout.kind, .quarters)
            XCTAssertEqual(match.coveredZoneIDs, [zoneID])
        }
    }

    func testInfersAndPreservesSymmetricGaps() throws {
        let gappedLeftHalf = CGRect(x: 10, y: 10, width: 585, height: 780)
        let match = try XCTUnwrap(SnapEngine.detect(
            windowFrame: gappedLeftHalf,
            screenFrame: screen,
            tolerance: 24
        ))

        XCTAssertEqual(match.layout.kind, .halves)
        XCTAssertEqual(match.layout.zoneFrames[0], gappedLeftHalf)
        XCTAssertEqual(match.layout.zoneFrames[1], CGRect(x: 605, y: 10, width: 585, height: 780))
    }

    func testHandlesDisplaysWithNegativeOrigins() throws {
        let externalScreen = CGRect(x: -1440, y: 180, width: 1440, height: 900)
        let window = CGRect(x: -1440, y: 180, width: 480, height: 900)

        let match = try XCTUnwrap(SnapEngine.detect(windowFrame: window, screenFrame: externalScreen))

        XCTAssertEqual(match.layout.kind, .thirds)
        XCTAssertEqual(match.coveredZoneIDs, [0])
    }

    func testRejectsFloatingWindow() {
        let result = SnapEngine.detect(
            windowFrame: CGRect(x: 137, y: 91, width: 731, height: 522),
            screenFrame: screen
        )

        XCTAssertNil(result)
    }

    func testAssignsExistingWindowsToAtomicZones() throws {
        let match = try XCTUnwrap(SnapEngine.detect(
            windowFrame: CGRect(x: 0, y: 0, width: 400, height: 800),
            screenFrame: screen
        ))
        let windows = [
            CGRect(x: 0, y: 0, width: 400, height: 800),
            CGRect(x: 400, y: 0, width: 800, height: 800),
            CGRect(x: 90, y: 80, width: 300, height: 300),
        ]

        let assignments = SnapEngine.assign(windows: windows, to: match.layout)

        XCTAssertEqual(assignments[0], [0])
        XCTAssertEqual(assignments[1], [1, 2])
        XCTAssertNil(assignments[2])
    }
}

