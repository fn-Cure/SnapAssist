import CoreGraphics
import Foundation

public enum LayoutKind: String, CaseIterable, Sendable {
    case halves
    case thirds
    case quarters

    public var columns: Int {
        switch self {
        case .halves, .quarters: 2
        case .thirds: 3
        }
    }

    public var rows: Int {
        self == .quarters ? 2 : 1
    }
}

public struct LayoutInsets: Equatable, Sendable {
    public var left: CGFloat
    public var right: CGFloat
    public var bottom: CGFloat
    public var top: CGFloat

    public init(left: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0, top: CGFloat = 0) {
        self.left = left
        self.right = right
        self.bottom = bottom
        self.top = top
    }
}

public struct LayoutGeometry: Equatable, Sendable {
    public let kind: LayoutKind
    public let screenFrame: CGRect
    public let insets: LayoutInsets
    public let columnGap: CGFloat
    public let rowGap: CGFloat
    public let zoneFrames: [CGRect]

    public init(
        kind: LayoutKind,
        screenFrame: CGRect,
        insets: LayoutInsets = LayoutInsets(),
        columnGap: CGFloat = 0,
        rowGap: CGFloat = 0
    ) {
        self.kind = kind
        self.screenFrame = screenFrame
        self.insets = insets
        self.columnGap = max(0, columnGap)
        self.rowGap = max(0, rowGap)
        self.zoneFrames = LayoutGeometry.makeZoneFrames(
            kind: kind,
            screenFrame: screenFrame,
            insets: insets,
            columnGap: max(0, columnGap),
            rowGap: max(0, rowGap)
        )
    }

    private static func makeZoneFrames(
        kind: LayoutKind,
        screenFrame: CGRect,
        insets: LayoutInsets,
        columnGap: CGFloat,
        rowGap: CGFloat
    ) -> [CGRect] {
        let columns = kind.columns
        let rows = kind.rows
        let usableWidth = max(
            0,
            screenFrame.width - insets.left - insets.right - CGFloat(columns - 1) * columnGap
        )
        let usableHeight = max(
            0,
            screenFrame.height - insets.bottom - insets.top - CGFloat(rows - 1) * rowGap
        )
        let cellWidth = usableWidth / CGFloat(columns)
        let cellHeight = usableHeight / CGFloat(rows)
        var frames: [CGRect] = []

        for visualRow in 0..<rows {
            let bottomRow = rows - visualRow - 1
            for column in 0..<columns {
                frames.append(CGRect(
                    x: screenFrame.minX + insets.left + CGFloat(column) * (cellWidth + columnGap),
                    y: screenFrame.minY + insets.bottom + CGFloat(bottomRow) * (cellHeight + rowGap),
                    width: cellWidth,
                    height: cellHeight
                ))
            }
        }

        return frames
    }
}

public struct SnapMatch: Equatable, Sendable {
    public let layout: LayoutGeometry
    public let coveredZoneIDs: [Int]

    public init(layout: LayoutGeometry, coveredZoneIDs: [Int]) {
        self.layout = layout
        self.coveredZoneIDs = coveredZoneIDs.sorted()
    }
}

public enum SnapEngine {
    public static func detect(
        windowFrame: CGRect,
        screenFrame: CGRect,
        tolerance: CGFloat = 24
    ) -> SnapMatch? {
        guard windowFrame.width > 0,
              windowFrame.height > 0,
              screenFrame.insetBy(dx: -tolerance, dy: -tolerance).contains(windowFrame) else {
            return nil
        }

        let matches = candidates.compactMap { candidate -> (Candidate, CGFloat)? in
            let canonical = LayoutGeometry(kind: candidate.kind, screenFrame: screenFrame)
            let expected = candidate.frame(in: canonical)
            let score = edgeDistance(windowFrame, expected)
            return score <= tolerance ? (candidate, score) : nil
        }

        guard let best = matches.min(by: { $0.1 < $1.1 }) else {
            return nil
        }

        let metrics = inferMetrics(
            windowFrame: windowFrame,
            screenFrame: screenFrame,
            candidate: best.0,
            tolerance: tolerance
        )
        let layout = LayoutGeometry(
            kind: best.0.kind,
            screenFrame: screenFrame,
            insets: metrics.insets,
            columnGap: metrics.columnGap,
            rowGap: metrics.rowGap
        )

        return SnapMatch(layout: layout, coveredZoneIDs: best.0.zoneIDs)
    }

    public static func assign(
        windows: [CGRect],
        to layout: LayoutGeometry,
        tolerance: CGFloat = 24
    ) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        let layoutCandidates = candidates.filter { $0.kind == layout.kind }

        for (index, frame) in windows.enumerated() {
            let matches = layoutCandidates.map { candidate in
                (candidate, edgeDistance(frame, candidate.frame(in: layout)))
            }.filter { $0.1 <= tolerance }

            if let best = matches.min(by: { $0.1 < $1.1 }) {
                result[index] = best.0.zoneIDs
            }
        }

        return result
    }

    private struct Candidate {
        let kind: LayoutKind
        let columnStart: Int
        let columnSpan: Int
        let bottomRowStart: Int
        let rowSpan: Int
        let zoneIDs: [Int]

        func frame(in layout: LayoutGeometry) -> CGRect {
            zoneIDs.dropFirst().reduce(layout.zoneFrames[zoneIDs[0]]) { partial, zoneID in
                partial.union(layout.zoneFrames[zoneID])
            }
        }
    }

    private struct InferredMetrics {
        let insets: LayoutInsets
        let columnGap: CGFloat
        let rowGap: CGFloat
    }

    private static let candidates: [Candidate] = [
        Candidate(kind: .halves, columnStart: 0, columnSpan: 1, bottomRowStart: 0, rowSpan: 1, zoneIDs: [0]),
        Candidate(kind: .halves, columnStart: 1, columnSpan: 1, bottomRowStart: 0, rowSpan: 1, zoneIDs: [1]),
        Candidate(kind: .thirds, columnStart: 0, columnSpan: 1, bottomRowStart: 0, rowSpan: 1, zoneIDs: [0]),
        Candidate(kind: .thirds, columnStart: 1, columnSpan: 1, bottomRowStart: 0, rowSpan: 1, zoneIDs: [1]),
        Candidate(kind: .thirds, columnStart: 2, columnSpan: 1, bottomRowStart: 0, rowSpan: 1, zoneIDs: [2]),
        Candidate(kind: .thirds, columnStart: 0, columnSpan: 2, bottomRowStart: 0, rowSpan: 1, zoneIDs: [0, 1]),
        Candidate(kind: .thirds, columnStart: 1, columnSpan: 2, bottomRowStart: 0, rowSpan: 1, zoneIDs: [1, 2]),
        Candidate(kind: .quarters, columnStart: 0, columnSpan: 1, bottomRowStart: 1, rowSpan: 1, zoneIDs: [0]),
        Candidate(kind: .quarters, columnStart: 1, columnSpan: 1, bottomRowStart: 1, rowSpan: 1, zoneIDs: [1]),
        Candidate(kind: .quarters, columnStart: 0, columnSpan: 1, bottomRowStart: 0, rowSpan: 1, zoneIDs: [2]),
        Candidate(kind: .quarters, columnStart: 1, columnSpan: 1, bottomRowStart: 0, rowSpan: 1, zoneIDs: [3]),
    ]

    private static func inferMetrics(
        windowFrame: CGRect,
        screenFrame: CGRect,
        candidate: Candidate,
        tolerance: CGFloat
    ) -> InferredMetrics {
        let vertical = inferAxis(
            screenMin: screenFrame.minY,
            screenLength: screenFrame.height,
            actualMin: windowFrame.minY,
            actualLength: windowFrame.height,
            start: candidate.bottomRowStart,
            span: candidate.rowSpan,
            count: candidate.kind.rows,
            fallbackOuter: 0,
            tolerance: tolerance
        )
        let horizontalFallback = (vertical.leading + vertical.trailing) / 2
        let horizontal = inferAxis(
            screenMin: screenFrame.minX,
            screenLength: screenFrame.width,
            actualMin: windowFrame.minX,
            actualLength: windowFrame.width,
            start: candidate.columnStart,
            span: candidate.columnSpan,
            count: candidate.kind.columns,
            fallbackOuter: horizontalFallback,
            tolerance: tolerance
        )

        return InferredMetrics(
            insets: LayoutInsets(
                left: horizontal.leading,
                right: horizontal.trailing,
                bottom: vertical.leading,
                top: vertical.trailing
            ),
            columnGap: horizontal.gap,
            rowGap: vertical.gap
        )
    }

    private static func inferAxis(
        screenMin: CGFloat,
        screenLength: CGFloat,
        actualMin: CGFloat,
        actualLength: CGFloat,
        start: Int,
        span: Int,
        count: Int,
        fallbackOuter: CGFloat,
        tolerance: CGFloat
    ) -> (leading: CGFloat, trailing: CGFloat, gap: CGFloat) {
        let actualMax = actualMin + actualLength
        let screenMax = screenMin + screenLength
        let observedLeading = start == 0 ? actualMin - screenMin : nil
        let observedTrailing = start + span == count ? screenMax - actualMax : nil
        let leading = clampInset(observedLeading ?? observedTrailing ?? fallbackOuter, tolerance: tolerance)
        let trailing = clampInset(observedTrailing ?? observedLeading ?? fallbackOuter, tolerance: tolerance)

        guard count > 1 else {
            return (leading, trailing, 0)
        }

        let spanFraction = CGFloat(span) / CGFloat(count)
        let coefficient = CGFloat(span - 1) - CGFloat(span * (count - 1)) / CGFloat(count)
        guard abs(coefficient) > 0.0001 else {
            return (leading, trailing, 0)
        }

        let widthWithoutGaps = spanFraction * (screenLength - leading - trailing)
        let inferredGap = (actualLength - widthWithoutGaps) / coefficient
        return (leading, trailing, max(0, min(inferredGap, tolerance * 2)))
    }

    private static func clampInset(_ value: CGFloat, tolerance: CGFloat) -> CGFloat {
        max(0, min(value, tolerance * 2))
    }

    private static func edgeDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        max(
            abs(lhs.minX - rhs.minX),
            abs(lhs.minY - rhs.minY),
            abs(lhs.maxX - rhs.maxX),
            abs(lhs.maxY - rhs.maxY)
        )
    }
}
