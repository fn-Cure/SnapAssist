import CoreGraphics
import XCTest
@testable import SnapAssistCore

final class CoordinateConverterTests: XCTestCase {
    func testConvertsBetweenAXAndCocoaCoordinates() {
        let cocoa = CGRect(x: -1440, y: 180, width: 480, height: 900)

        let ax = ScreenCoordinateConverter.cocoaToAX(cocoa, primaryScreenHeight: 1117)
        let roundTrip = ScreenCoordinateConverter.axToCocoa(ax, primaryScreenHeight: 1117)

        XCTAssertEqual(ax, CGRect(x: -1440, y: 37, width: 480, height: 900))
        XCTAssertEqual(roundTrip, cocoa)
    }
}

