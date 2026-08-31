import CoreGraphics
import Foundation

public enum WindowEventDisposition: Equatable, Sendable {
    case user
    case programmatic(operationID: UUID)
}

public struct PendingWindowMutation: Equatable, Sendable {
    public let operationID: UUID
    public let windowID: String
    public let expectedFrame: CGRect
    public let tolerance: CGFloat
    public let expiresAt: TimeInterval

    public init(
        operationID: UUID,
        windowID: String,
        expectedFrame: CGRect,
        tolerance: CGFloat,
        expiresAt: TimeInterval
    ) {
        self.operationID = operationID
        self.windowID = windowID
        self.expectedFrame = expectedFrame
        self.tolerance = tolerance
        self.expiresAt = expiresAt
    }
}

public struct WindowMutationLedger: Sendable {
    private var pending: [String: PendingWindowMutation] = [:]

    public init() {}

    public mutating func register(
        operationID: UUID,
        windowID: String,
        expectedFrame: CGRect,
        tolerance: CGFloat = 4,
        expiresAt: TimeInterval
    ) {
        pending[windowID] = PendingWindowMutation(
            operationID: operationID,
            windowID: windowID,
            expectedFrame: expectedFrame,
            tolerance: tolerance,
            expiresAt: expiresAt
        )
    }

    public mutating func classify(
        windowID: String,
        actualFrame: CGRect,
        at timestamp: TimeInterval
    ) -> WindowEventDisposition {
        guard let mutation = pending[windowID] else { return .user }
        guard timestamp <= mutation.expiresAt else {
            pending.removeValue(forKey: windowID)
            return .user
        }
        guard actualFrame.isApproximatelyEqual(to: mutation.expectedFrame, tolerance: mutation.tolerance) else {
            return .user
        }
        pending.removeValue(forKey: windowID)
        return .programmatic(operationID: mutation.operationID)
    }

    public mutating func cancelAll() {
        pending.removeAll()
    }

    public mutating func cancel(windowID: String) {
        pending.removeValue(forKey: windowID)
    }
}

public enum LayoutGroupValidator {
    public static func isValid(
        _ group: LayoutGroup,
        windows: [WindowDescriptor],
        tolerance: CGFloat = 6
    ) -> Bool {
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let assignedZones = group.members.values.flatMap { $0 }
        guard !group.members.isEmpty,
              assignedZones.count == Set(assignedZones).count,
              assignedZones.allSatisfy(group.layout.zoneFrames.indices.contains) else {
            return false
        }

        for windowID in group.members.keys {
            guard let window = windowsByID[windowID],
                  window.screenID == group.screenID,
                  !window.isMinimized,
                  !window.isSystemWindow,
                  !window.isModal,
                  !window.isFullScreen,
                  window.isMovable,
                  window.isResizable,
                  let verifiedFrame = group.verifiedFrames[windowID],
                  window.frame.isApproximatelyEqual(to: verifiedFrame, tolerance: tolerance) else {
                return false
            }
        }
        return true
    }
}

public struct SnapRuntimeState: Sendable {
    public private(set) var groups: [String: LayoutGroup] = [:]
    public private(set) var activeSession: AssistSession?
    private var presentationGeneration: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func install(_ session: AssistSession) -> UInt64 {
        let incomingIDs = Set(session.group.members.keys)
        groups = groups.filter { screenID, group in
            screenID == session.group.screenID || incomingIDs.isDisjoint(with: group.members.keys)
        }
        groups[session.group.screenID] = session.group
        activeSession = session
        return bumpGeneration()
    }

    @discardableResult
    public mutating func updateSession(_ session: AssistSession) -> UInt64 {
        install(session)
    }

    public mutating func cancelSession(removeIncompleteGroup: Bool) {
        if removeIncompleteGroup,
           let group = activeSession?.group,
           !group.isComplete {
            groups.removeValue(forKey: group.screenID)
        }
        activeSession = nil
        _ = bumpGeneration()
    }

    public mutating func invalidate(windowID: String) {
        let affectedScreens = groups.compactMap { screenID, group in
            group.members[windowID] == nil ? nil : screenID
        }
        affectedScreens.forEach { groups.removeValue(forKey: $0) }
        if let session = activeSession,
           session.group.members[windowID] != nil || session.candidates.contains(where: { $0.id == windowID }) {
            activeSession = nil
        }
        _ = bumpGeneration()
    }

    public mutating func invalidateAll() {
        groups.removeAll()
        activeSession = nil
        _ = bumpGeneration()
    }

    public mutating func updateVerifiedFrames(screenID: String, frames: [String: CGRect]) {
        guard var group = groups[screenID], Set(frames.keys) == Set(group.members.keys) else { return }
        group.verifiedFrames = frames
        groups[screenID] = group
        if var session = activeSession, session.group.screenID == screenID {
            session.group = group
            activeSession = session
        }
        _ = bumpGeneration()
    }

    public mutating func reconcile(with windows: [WindowDescriptor]) {
        let validScreens = Set(groups.compactMap { screenID, group in
            LayoutGroupValidator.isValid(group, windows: windows) ? screenID : nil
        })
        groups = groups.filter { validScreens.contains($0.key) }

        guard var session = activeSession,
              validScreens.contains(session.group.screenID) else {
            if activeSession != nil {
                activeSession = nil
                _ = bumpGeneration()
            }
            return
        }
        let visibleIDs = Set(windows.map(\.id))
        let previousCandidates = session.candidates
        session.candidates.removeAll { !visibleIDs.contains($0.id) }
        if session.candidates.isEmpty && !session.emptyZoneIDs.isEmpty {
            groups.removeValue(forKey: session.group.screenID)
            activeSession = nil
            _ = bumpGeneration()
            return
        }
        if session.candidates != previousCandidates {
            activeSession = session
            _ = bumpGeneration()
        }
    }

    public func isCurrentPresentation(_ generation: UInt64) -> Bool {
        generation == presentationGeneration
    }

    private mutating func bumpGeneration() -> UInt64 {
        presentationGeneration &+= 1
        return presentationGeneration
    }
}

public extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

public extension CGPoint {
    func isApproximatelyEqual(to other: CGPoint, tolerance: CGFloat) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

public extension CGSize {
    func isApproximatelyEqual(to other: CGSize, tolerance: CGFloat) -> Bool {
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
