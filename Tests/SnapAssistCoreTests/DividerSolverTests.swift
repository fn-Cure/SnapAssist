import CoreGraphics
import XCTest
@testable import SnapAssistCore

final class DividerSolverTests: XCTestCase {
    func testResizesBothHalvesAroundSharedDivider() throws {
        let members = [
            LayoutMember(id: "left", frame: CGRect(x: 0, y: 0, width: 600, height: 800)),
            LayoutMember(id: "right", frame: CGRect(x: 600, y: 0, width: 600, height: 800)),
        ]
        let divider = try XCTUnwrap(DividerSolver.findDivider(
            at: CGPoint(x: 600, y: 300),
            members: members
        ))

        let result = DividerSolver.resize(divider: divider, to: 700, members: members)

        XCTAssertEqual(result["left"], CGRect(x: 0, y: 0, width: 700, height: 800))
        XCTAssertEqual(result["right"], CGRect(x: 700, y: 0, width: 500, height: 800))
    }

    func testMovesEveryWindowAlongAQuarterLayoutSeparator() throws {
        let members = [
            LayoutMember(id: "topLeft", frame: CGRect(x: 0, y: 400, width: 600, height: 400)),
            LayoutMember(id: "topRight", frame: CGRect(x: 600, y: 400, width: 600, height: 400)),
            LayoutMember(id: "bottomLeft", frame: CGRect(x: 0, y: 0, width: 600, height: 400)),
            LayoutMember(id: "bottomRight", frame: CGRect(x: 600, y: 0, width: 600, height: 400)),
        ]
        let divider = try XCTUnwrap(DividerSolver.findDivider(
            at: CGPoint(x: 600, y: 650),
            members: members
        ))

        let result = DividerSolver.resize(divider: divider, to: 525, members: members)

        XCTAssertEqual(result["topLeft"]?.width, 525)
        XCTAssertEqual(result["bottomLeft"]?.width, 525)
        XCTAssertEqual(result["topRight"], CGRect(x: 525, y: 400, width: 675, height: 400))
        XCTAssertEqual(result["bottomRight"], CGRect(x: 525, y: 0, width: 675, height: 400))
    }

    func testPreservesGapWhileResizing() throws {
        let members = [
            LayoutMember(id: "left", frame: CGRect(x: 10, y: 10, width: 585, height: 780)),
            LayoutMember(id: "right", frame: CGRect(x: 605, y: 10, width: 585, height: 780)),
        ]
        let divider = try XCTUnwrap(DividerSolver.findDivider(
            at: CGPoint(x: 600, y: 300),
            members: members
        ))

        let result = DividerSolver.resize(divider: divider, to: 700, members: members)

        XCTAssertEqual(result["left"]?.maxX, 695)
        XCTAssertEqual(result["right"]?.minX, 705)
    }

    func testClampsDividerToEveryMembersMinimumSize() throws {
        let members = [
            LayoutMember(
                id: "left",
                frame: CGRect(x: 0, y: 0, width: 600, height: 800),
                minimumSize: CGSize(width: 300, height: 120)
            ),
            LayoutMember(
                id: "right",
                frame: CGRect(x: 600, y: 0, width: 600, height: 800),
                minimumSize: CGSize(width: 400, height: 120)
            ),
        ]
        let divider = try XCTUnwrap(DividerSolver.findDivider(
            at: CGPoint(x: 600, y: 300),
            members: members
        ))

        let result = DividerSolver.resize(divider: divider, to: 1_000, members: members)

        XCTAssertEqual(result["left"]?.width, 800)
        XCTAssertEqual(result["right"]?.width, 400)
    }

    func testResizesHorizontalSeparatorAcrossQuarterLayout() throws {
        let members = [
            LayoutMember(id: "topLeft", frame: CGRect(x: 0, y: 400, width: 600, height: 400)),
            LayoutMember(id: "topRight", frame: CGRect(x: 600, y: 400, width: 600, height: 400)),
            LayoutMember(id: "bottomLeft", frame: CGRect(x: 0, y: 0, width: 600, height: 400)),
            LayoutMember(id: "bottomRight", frame: CGRect(x: 600, y: 0, width: 600, height: 400)),
        ]
        let divider = try XCTUnwrap(DividerSolver.findDivider(
            at: CGPoint(x: 200, y: 400),
            members: members
        ))

        let result = DividerSolver.resize(divider: divider, to: 475, members: members)

        XCTAssertEqual(result["bottomLeft"]?.height, 475)
        XCTAssertEqual(result["bottomRight"]?.height, 475)
        XCTAssertEqual(result["topLeft"], CGRect(x: 0, y: 475, width: 600, height: 325))
        XCTAssertEqual(result["topRight"], CGRect(x: 600, y: 475, width: 600, height: 325))
    }

    func testRejectsPointerAwayFromSharedDivider() {
        let members = [
            LayoutMember(id: "left", frame: CGRect(x: 0, y: 0, width: 600, height: 800)),
            LayoutMember(id: "right", frame: CGRect(x: 600, y: 0, width: 600, height: 800)),
        ]

        XCTAssertNil(DividerSolver.findDivider(at: CGPoint(x: 450, y: 300), members: members))
    }
}

