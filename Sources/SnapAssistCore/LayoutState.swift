import CoreGraphics
import Foundation

public struct WindowDescriptor: Equatable, Sendable, Identifiable {
    public let id: String
    public let processID: Int32
    public let appName: String
    public let title: String
    public var frame: CGRect
    public let screenID: String
    public let zOrder: Int
    public let isMinimized: Bool
    public let isMovable: Bool
    public let isResizable: Bool
    public let isSystemWindow: Bool
    public let isOnVisibleSpace: Bool

    public init(
        id: String,
        processID: Int32,
        appName: String,
        title: String,
        frame: CGRect,
        screenID: String,
        zOrder: Int,
        isMinimized: Bool,
        isMovable: Bool,
        isResizable: Bool,
        isSystemWindow: Bool,
        isOnVisibleSpace: Bool = true
    ) {
        self.id = id
        self.processID = processID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.screenID = screenID
        self.zOrder = zOrder
        self.isMinimized = isMinimized
        self.isMovable = isMovable
        self.isResizable = isResizable
        self.isSystemWindow = isSystemWindow
        self.isOnVisibleSpace = isOnVisibleSpace
    }
}

public enum CandidateFilter {
    public static func eligibleWindows(
        from windows: [WindowDescriptor],
        excluding excludedIDs: Set<String>,
        ownProcessID: Int32
    ) -> [WindowDescriptor] {
        windows.filter { window in
            !excludedIDs.contains(window.id)
                && window.processID != ownProcessID
                && window.isOnVisibleSpace
                && !window.isMinimized
                && !window.isSystemWindow
                && window.isMovable
                && window.isResizable
                && window.frame.width >= 80
                && window.frame.height >= 60
        }.sorted {
            if $0.zOrder == $1.zOrder {
                return $0.id < $1.id
            }
            return $0.zOrder < $1.zOrder
        }
    }
}

public struct LayoutGroup: Equatable, Sendable {
    public let screenID: String
    public let layout: LayoutGeometry
    public var members: [String: [Int]]

    public init(screenID: String, layout: LayoutGeometry, members: [String: [Int]]) {
        self.screenID = screenID
        self.layout = layout
        self.members = members
    }
}

public struct AssistSession: Equatable, Sendable {
    public var group: LayoutGroup
    public var candidates: [WindowDescriptor]

    public var emptyZoneIDs: [Int] {
        let occupied = Set(group.members.values.flatMap { $0 })
        return group.layout.zoneFrames.indices.filter { !occupied.contains($0) }
    }

    public mutating func place(windowID: String, into zoneID: Int) -> CGRect? {
        guard emptyZoneIDs.contains(zoneID),
              let candidateIndex = candidates.firstIndex(where: { $0.id == windowID }) else {
            return nil
        }

        group.members[windowID] = [zoneID]
        candidates.remove(at: candidateIndex)
        return group.layout.zoneFrames[zoneID]
    }
}

public enum LayoutStateBuilder {
    public static func buildSession(
        trigger: WindowDescriptor,
        windowsOnTargetScreen: [WindowDescriptor],
        allVisibleWindows: [WindowDescriptor],
        screenFrame: CGRect,
        ownProcessID: Int32,
        tolerance: CGFloat = 24
    ) -> AssistSession? {
        guard let match = SnapEngine.detect(
            windowFrame: trigger.frame,
            screenFrame: screenFrame,
            tolerance: tolerance
        ) else {
            return nil
        }

        let sortedTargetWindows = windowsOnTargetScreen.sorted { $0.zOrder < $1.zOrder }
        let assignments = SnapEngine.assign(
            windows: sortedTargetWindows.map(\.frame),
            to: match.layout,
            tolerance: tolerance
        )
        var claimedZones: Set<Int> = []
        var members: [String: [Int]] = [:]

        for index in sortedTargetWindows.indices {
            guard let zones = assignments[index], claimedZones.isDisjoint(with: zones) else {
                continue
            }
            members[sortedTargetWindows[index].id] = zones
            claimedZones.formUnion(zones)
        }

        members[trigger.id] = match.coveredZoneIDs
        let occupiedIDs = Set(members.keys)
        let candidates = CandidateFilter.eligibleWindows(
            from: allVisibleWindows,
            excluding: occupiedIDs,
            ownProcessID: ownProcessID
        )

        return AssistSession(
            group: LayoutGroup(screenID: trigger.screenID, layout: match.layout, members: members),
            candidates: candidates
        )
    }
}

public struct WindowEventGate: Sendable {
    public let cooldown: TimeInterval
    private var suppressions: [String: TimeInterval] = [:]
    private var lastHandled: [String: (frame: CGRect, timestamp: TimeInterval)] = [:]

    public init(cooldown: TimeInterval = 1.0) {
        self.cooldown = cooldown
    }

    public mutating func suppress(windowID: String, until timestamp: TimeInterval) {
        suppressions[windowID] = timestamp
    }

    public mutating func shouldHandle(
        windowID: String,
        frame: CGRect,
        at timestamp: TimeInterval
    ) -> Bool {
        if let suppressedUntil = suppressions[windowID] {
            if timestamp < suppressedUntil {
                return false
            }
            suppressions.removeValue(forKey: windowID)
        }

        if let previous = lastHandled[windowID],
           previous.frame == frame,
           timestamp - previous.timestamp < cooldown {
            return false
        }

        lastHandled[windowID] = (frame, timestamp)
        return true
    }
}

