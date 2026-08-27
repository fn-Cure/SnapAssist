import CoreGraphics
import XCTest
@testable import SnapAssistCore

final class LayoutStateTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testCandidateFilterKeepsEligibleWindowsFromEveryDisplay() {
        let windows = [
            window(id: "trigger", pid: 1, frame: CGRect(x: 0, y: 0, width: 600, height: 800)),
            window(id: "otherDisplay", pid: 2, screenID: "external"),
            window(id: "minimized", pid: 3, isMinimized: true),
            window(id: "system", pid: 4, isSystemWindow: true),
            window(id: "fixed", pid: 5, isResizable: false),
            window(id: "self", pid: 99),
        ]

        let candidates = CandidateFilter.eligibleWindows(
            from: windows,
            excluding: ["trigger"],
            ownProcessID: 99
        )

        XCTAssertEqual(candidates.map(\.id), ["otherDisplay"])
    }

    func testBuildsAssistSessionForEveryEmptyZone() throws {
        let trigger = window(
            id: "left",
            pid: 1,
            frame: CGRect(x: 0, y: 0, width: 400, height: 800)
        )
        let candidate = window(id: "candidate", pid: 2, screenID: "external")

        let session = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: trigger,
            windowsOnTargetScreen: [trigger],
            allVisibleWindows: [trigger, candidate],
            screenFrame: screen,
            ownProcessID: 99
        ))

        XCTAssertEqual(session.group.layout.kind, .thirds)
        XCTAssertEqual(session.group.members["left"], [0])
        XCTAssertEqual(session.emptyZoneIDs, [1, 2])
        XCTAssertEqual(session.candidates.map(\.id), ["candidate"])
    }

    func testExistingOccupancyRemovesAlreadyFilledZones() throws {
        let left = window(id: "left", pid: 1, frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let right = window(id: "right", pid: 2, frame: CGRect(x: 600, y: 0, width: 600, height: 800))

        let session = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: left,
            windowsOnTargetScreen: [left, right],
            allVisibleWindows: [left, right],
            screenFrame: screen,
            ownProcessID: 99
        ))

        XCTAssertEqual(session.group.members["left"], [0])
        XCTAssertEqual(session.group.members["right"], [1])
        XCTAssertTrue(session.emptyZoneIDs.isEmpty)
    }

    func testSelectingCandidateFillsZoneAndRemovesCandidate() throws {
        let trigger = window(id: "left", pid: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let candidate = window(id: "candidate", pid: 2, screenID: "external")
        var session = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: trigger,
            windowsOnTargetScreen: [trigger],
            allVisibleWindows: [trigger, candidate],
            screenFrame: screen,
            ownProcessID: 99
        ))

        let targetFrame = try XCTUnwrap(session.place(windowID: "candidate", into: 1))

        XCTAssertEqual(targetFrame, CGRect(x: 400, y: 0, width: 400, height: 800))
        XCTAssertEqual(session.group.members["candidate"], [1])
        XCTAssertEqual(session.emptyZoneIDs, [2])
        XCTAssertTrue(session.candidates.isEmpty)
    }

    func testEventGateSuppressesProgrammaticAndDuplicateEvents() {
        var gate = WindowEventGate(cooldown: 1.0)
        let frame = CGRect(x: 0, y: 0, width: 600, height: 800)

        gate.suppress(windowID: "window", until: 10.5)
        XCTAssertFalse(gate.shouldHandle(windowID: "window", frame: frame, at: 10.2))
        XCTAssertTrue(gate.shouldHandle(windowID: "window", frame: frame, at: 10.6))
        XCTAssertFalse(gate.shouldHandle(windowID: "window", frame: frame, at: 11.0))
        XCTAssertTrue(gate.shouldHandle(windowID: "window", frame: frame, at: 11.7))
    }

    private func window(
        id: String,
        pid: Int32,
        screenID: String = "main",
        frame: CGRect = CGRect(x: 100, y: 100, width: 500, height: 500),
        isMinimized: Bool = false,
        isMovable: Bool = true,
        isResizable: Bool = true,
        isSystemWindow: Bool = false
    ) -> WindowDescriptor {
        WindowDescriptor(
            id: id,
            processID: pid,
            appName: id,
            title: id,
            frame: frame,
            screenID: screenID,
            zOrder: 0,
            isMinimized: isMinimized,
            isMovable: isMovable,
            isResizable: isResizable,
            isSystemWindow: isSystemWindow
        )
    }
}

