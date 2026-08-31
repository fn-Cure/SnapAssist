import CoreGraphics
import XCTest
@testable import SnapAssistCore

final class RuntimeStateTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testInstallingSessionRemovesWindowFromPreviousGroup() throws {
        let left = window(id: "left", frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let right = window(id: "right", frame: CGRect(x: 600, y: 0, width: 600, height: 800))
        let movedRight = window(
            id: "right",
            screenID: "external",
            frame: CGRect(x: 0, y: 0, width: 400, height: 800)
        )

        let halfSession = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: left,
            windowsOnTargetScreen: [left, right],
            allVisibleWindows: [left, right],
            screenFrame: screen,
            ownProcessID: 999
        ))
        let thirdsSession = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: movedRight,
            windowsOnTargetScreen: [movedRight],
            allVisibleWindows: [left, movedRight],
            screenFrame: screen,
            ownProcessID: 999
        ))

        var state = SnapRuntimeState()
        state.install(halfSession)
        state.install(thirdsSession)

        let memberships = state.groups.values.filter { $0.members[movedRight.id] != nil }
        XCTAssertEqual(memberships.count, 1)
        XCTAssertNil(state.groups["main"])
    }

    func testReconcileInvalidatesGroupWhenMemberMovesDisplay() throws {
        let left = window(id: "left", frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let right = window(id: "right", frame: CGRect(x: 600, y: 0, width: 600, height: 800))
        let session = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: left,
            windowsOnTargetScreen: [left, right],
            allVisibleWindows: [left, right],
            screenFrame: screen,
            ownProcessID: 999
        ))
        var state = SnapRuntimeState()
        state.install(session)

        let movedRight = window(
            id: "right",
            screenID: "external",
            frame: CGRect(x: 1300, y: 0, width: 600, height: 800)
        )
        state.reconcile(with: [left, movedRight])

        XCTAssertTrue(state.groups.isEmpty)
        XCTAssertNil(state.activeSession)
    }

    func testInvalidatingTriggerCancelsPresentationGeneration() throws {
        let trigger = window(id: "trigger", frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let candidate = window(id: "candidate", screenID: "external")
        let session = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: trigger,
            windowsOnTargetScreen: [trigger],
            allVisibleWindows: [trigger, candidate],
            screenFrame: screen,
            ownProcessID: 999
        ))
        var state = SnapRuntimeState()
        let firstGeneration = state.install(session)

        state.invalidate(windowID: trigger.id)

        XCTAssertFalse(state.isCurrentPresentation(firstGeneration))
        XCTAssertNil(state.activeSession)
        XCTAssertTrue(state.groups.isEmpty)
    }

    func testIncompleteGroupIsNotResizeEligible() throws {
        let trigger = window(id: "trigger", frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let session = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: trigger,
            windowsOnTargetScreen: [trigger],
            allVisibleWindows: [trigger],
            screenFrame: screen,
            ownProcessID: 999
        ))

        XCTAssertFalse(session.group.isComplete)
    }

    func testCandidateDisappearingCancelsEmptyPickerSession() throws {
        let trigger = window(id: "trigger", frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let candidate = window(id: "candidate", screenID: "external")
        let session = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: trigger,
            windowsOnTargetScreen: [trigger],
            allVisibleWindows: [trigger, candidate],
            screenFrame: screen,
            ownProcessID: 999
        ))
        var state = SnapRuntimeState()
        state.install(session)

        state.reconcile(with: [trigger])

        XCTAssertNil(state.activeSession)
        XCTAssertTrue(state.groups.isEmpty)
    }

    func testVerifiedLinkedResizeFramesRemainValidDuringReconciliation() throws {
        let left = window(id: "left", frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let right = window(id: "right", frame: CGRect(x: 600, y: 0, width: 600, height: 800))
        let session = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: left,
            windowsOnTargetScreen: [left, right],
            allVisibleWindows: [left, right],
            screenFrame: screen,
            ownProcessID: 999
        ))
        var state = SnapRuntimeState()
        state.install(session)

        let resizedFrames = [
            "left": CGRect(x: 0, y: 0, width: 700, height: 800),
            "right": CGRect(x: 700, y: 0, width: 500, height: 800),
        ]
        state.updateVerifiedFrames(screenID: "main", frames: resizedFrames)
        state.reconcile(with: [
            window(id: "left", frame: resizedFrames["left"]!),
            window(id: "right", frame: resizedFrames["right"]!),
        ])

        XCTAssertNotNil(state.groups["main"])
    }

    func testCancellingPickerDiscardsIncompleteGroupButPreservesCompleteGroup() throws {
        let partial = window(id: "partial", frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let partialSession = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: partial,
            windowsOnTargetScreen: [partial],
            allVisibleWindows: [partial],
            screenFrame: screen,
            ownProcessID: 999
        ))
        var state = SnapRuntimeState()
        state.install(partialSession)
        state.cancelSession(removeIncompleteGroup: true)
        XCTAssertTrue(state.groups.isEmpty)

        let left = window(id: "left", frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let right = window(id: "right", frame: CGRect(x: 600, y: 0, width: 600, height: 800))
        let completeSession = try XCTUnwrap(LayoutStateBuilder.buildSession(
            trigger: left,
            windowsOnTargetScreen: [left, right],
            allVisibleWindows: [left, right],
            screenFrame: screen,
            ownProcessID: 999
        ))
        state.install(completeSession)
        state.cancelSession(removeIncompleteGroup: true)
        XCTAssertNotNil(state.groups["main"])
    }

    private func window(
        id: String,
        screenID: String = "main",
        frame: CGRect = CGRect(x: 100, y: 100, width: 500, height: 500)
    ) -> WindowDescriptor {
        WindowDescriptor(
            id: id,
            processID: 1,
            appName: id,
            title: id,
            frame: frame,
            screenID: screenID,
            zOrder: 0,
            isMinimized: false,
            isMovable: true,
            isResizable: true,
            isSystemWindow: false
        )
    }
}
