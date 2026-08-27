import CoreGraphics
import Foundation

public struct LayoutMember: Equatable, Sendable {
    public let id: String
    public var frame: CGRect
    public var minimumSize: CGSize

    public init(
        id: String,
        frame: CGRect,
        minimumSize: CGSize = CGSize(width: 160, height: 120)
    ) {
        self.id = id
        self.frame = frame
        self.minimumSize = minimumSize
    }
}

public enum DividerOrientation: Sendable {
    case vertical
    case horizontal
}

public struct SharedDivider: Equatable, Sendable {
    public let orientation: DividerOrientation
    public let position: CGFloat
    public let gap: CGFloat
    public let leadingWindowIDs: Set<String>
    public let trailingWindowIDs: Set<String>

    public init(
        orientation: DividerOrientation,
        position: CGFloat,
        gap: CGFloat,
        leadingWindowIDs: Set<String>,
        trailingWindowIDs: Set<String>
    ) {
        self.orientation = orientation
        self.position = position
        self.gap = gap
        self.leadingWindowIDs = leadingWindowIDs
        self.trailingWindowIDs = trailingWindowIDs
    }
}

public enum DividerSolver {
    public static func findDivider(
        at point: CGPoint,
        members: [LayoutMember],
        tolerance: CGFloat = 12,
        maximumGap: CGFloat = 32
    ) -> SharedDivider? {
        let pairs = adjacentPairs(members: members, tolerance: tolerance, maximumGap: maximumGap)
        let candidates = pairs.filter { pair in
            switch pair.orientation {
            case .vertical:
                return abs(point.x - pair.position) <= tolerance + pair.gap / 2
                    && point.y >= pair.span.lowerBound - tolerance
                    && point.y <= pair.span.upperBound + tolerance
            case .horizontal:
                return abs(point.y - pair.position) <= tolerance + pair.gap / 2
                    && point.x >= pair.span.lowerBound - tolerance
                    && point.x <= pair.span.upperBound + tolerance
            }
        }

        guard let selected = candidates.min(by: { distance(from: point, to: $0) < distance(from: point, to: $1) }) else {
            return nil
        }

        let aligned = pairs.filter {
            $0.orientation == selected.orientation && abs($0.position - selected.position) <= tolerance
        }

        return SharedDivider(
            orientation: selected.orientation,
            position: selected.position,
            gap: aligned.map(\.gap).max() ?? selected.gap,
            leadingWindowIDs: Set(aligned.map(\.leadingID)),
            trailingWindowIDs: Set(aligned.map(\.trailingID))
        )
    }

    public static func resize(
        divider: SharedDivider,
        to proposedPosition: CGFloat,
        members: [LayoutMember]
    ) -> [String: CGRect] {
        let membersByID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let halfGap = divider.gap / 2
        var result = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.frame) })

        switch divider.orientation {
        case .vertical:
            let lowerBound = divider.leadingWindowIDs.compactMap { id -> CGFloat? in
                guard let member = membersByID[id] else { return nil }
                return member.frame.minX + member.minimumSize.width + halfGap
            }.max() ?? proposedPosition
            let upperBound = divider.trailingWindowIDs.compactMap { id -> CGFloat? in
                guard let member = membersByID[id] else { return nil }
                return member.frame.maxX - member.minimumSize.width - halfGap
            }.min() ?? proposedPosition
            let position = min(max(proposedPosition, lowerBound), upperBound)

            for id in divider.leadingWindowIDs {
                guard let member = membersByID[id] else { continue }
                var frame = member.frame
                frame.size.width = max(member.minimumSize.width, position - halfGap - frame.minX)
                result[id] = frame
            }
            for id in divider.trailingWindowIDs {
                guard let member = membersByID[id] else { continue }
                var frame = member.frame
                let maxX = frame.maxX
                frame.origin.x = position + halfGap
                frame.size.width = max(member.minimumSize.width, maxX - frame.minX)
                result[id] = frame
            }

        case .horizontal:
            let lowerBound = divider.leadingWindowIDs.compactMap { id -> CGFloat? in
                guard let member = membersByID[id] else { return nil }
                return member.frame.minY + member.minimumSize.height + halfGap
            }.max() ?? proposedPosition
            let upperBound = divider.trailingWindowIDs.compactMap { id -> CGFloat? in
                guard let member = membersByID[id] else { return nil }
                return member.frame.maxY - member.minimumSize.height - halfGap
            }.min() ?? proposedPosition
            let position = min(max(proposedPosition, lowerBound), upperBound)

            for id in divider.leadingWindowIDs {
                guard let member = membersByID[id] else { continue }
                var frame = member.frame
                frame.size.height = max(member.minimumSize.height, position - halfGap - frame.minY)
                result[id] = frame
            }
            for id in divider.trailingWindowIDs {
                guard let member = membersByID[id] else { continue }
                var frame = member.frame
                let maxY = frame.maxY
                frame.origin.y = position + halfGap
                frame.size.height = max(member.minimumSize.height, maxY - frame.minY)
                result[id] = frame
            }
        }

        return result
    }

    private struct AdjacentPair {
        let orientation: DividerOrientation
        let position: CGFloat
        let gap: CGFloat
        let leadingID: String
        let trailingID: String
        let span: ClosedRange<CGFloat>
    }

    private static func adjacentPairs(
        members: [LayoutMember],
        tolerance: CGFloat,
        maximumGap: CGFloat
    ) -> [AdjacentPair] {
        var pairs: [AdjacentPair] = []

        for firstIndex in members.indices {
            for secondIndex in members.indices where secondIndex > firstIndex {
                let first = members[firstIndex]
                let second = members[secondIndex]

                if let pair = verticalPair(first, second, tolerance: tolerance, maximumGap: maximumGap) {
                    pairs.append(pair)
                }
                if let pair = horizontalPair(first, second, tolerance: tolerance, maximumGap: maximumGap) {
                    pairs.append(pair)
                }
            }
        }

        return pairs
    }

    private static func verticalPair(
        _ first: LayoutMember,
        _ second: LayoutMember,
        tolerance: CGFloat,
        maximumGap: CGFloat
    ) -> AdjacentPair? {
        let ordered = first.frame.midX <= second.frame.midX ? (first, second) : (second, first)
        let rawGap = ordered.1.frame.minX - ordered.0.frame.maxX
        let overlapMin = max(ordered.0.frame.minY, ordered.1.frame.minY)
        let overlapMax = min(ordered.0.frame.maxY, ordered.1.frame.maxY)
        guard rawGap >= -tolerance, rawGap <= maximumGap, overlapMax - overlapMin > tolerance else {
            return nil
        }

        return AdjacentPair(
            orientation: .vertical,
            position: (ordered.0.frame.maxX + ordered.1.frame.minX) / 2,
            gap: max(0, rawGap),
            leadingID: ordered.0.id,
            trailingID: ordered.1.id,
            span: overlapMin...overlapMax
        )
    }

    private static func horizontalPair(
        _ first: LayoutMember,
        _ second: LayoutMember,
        tolerance: CGFloat,
        maximumGap: CGFloat
    ) -> AdjacentPair? {
        let ordered = first.frame.midY <= second.frame.midY ? (first, second) : (second, first)
        let rawGap = ordered.1.frame.minY - ordered.0.frame.maxY
        let overlapMin = max(ordered.0.frame.minX, ordered.1.frame.minX)
        let overlapMax = min(ordered.0.frame.maxX, ordered.1.frame.maxX)
        guard rawGap >= -tolerance, rawGap <= maximumGap, overlapMax - overlapMin > tolerance else {
            return nil
        }

        return AdjacentPair(
            orientation: .horizontal,
            position: (ordered.0.frame.maxY + ordered.1.frame.minY) / 2,
            gap: max(0, rawGap),
            leadingID: ordered.0.id,
            trailingID: ordered.1.id,
            span: overlapMin...overlapMax
        )
    }

    private static func distance(from point: CGPoint, to pair: AdjacentPair) -> CGFloat {
        switch pair.orientation {
        case .vertical: abs(point.x - pair.position)
        case .horizontal: abs(point.y - pair.position)
        }
    }
}

