import XCTest
@testable import SnapAssistCore

final class PickerNavigationTests: XCTestCase {
    func testCyclesZonesAndCandidates() {
        var navigation = PickerNavigation(zoneIDs: [1, 2], candidateIDs: ["a", "b", "c"])

        navigation.moveCandidate(by: 1)
        navigation.moveZone(by: 1)

        XCTAssertEqual(navigation.activeZoneID, 2)
        XCTAssertEqual(navigation.selectedCandidateID, "b")
    }

    func testNavigationWrapsInBothDirections() {
        var navigation = PickerNavigation(zoneIDs: [1, 2], candidateIDs: ["a", "b"])

        navigation.moveCandidate(by: -1)
        navigation.moveZone(by: -1)

        XCTAssertEqual(navigation.activeZoneID, 2)
        XCTAssertEqual(navigation.selectedCandidateID, "b")
    }

    func testRemovingCandidateKeepsSelectionValid() {
        var navigation = PickerNavigation(zoneIDs: [1], candidateIDs: ["a", "b"])
        navigation.moveCandidate(by: 1)

        navigation.removeCandidate("b")

        XCTAssertEqual(navigation.selectedCandidateID, "a")
    }
}

