import CoreGraphics
import Foundation

public enum FrameReadbackDecision: Equatable, Sendable {
    case pending
    case verified(CGRect)
    case mismatched(CGRect)
    case unavailable
}

public struct FrameReadbackVerifier: Sendable {
    public let requestedFrame: CGRect
    public let tolerance: CGFloat
    public let maximumSamples: Int

    private var sampleCount = 0

    public init(
        requestedFrame: CGRect,
        tolerance: CGFloat = 4,
        maximumSamples: Int = 10
    ) {
        precondition(maximumSamples > 0)
        self.requestedFrame = requestedFrame
        self.tolerance = tolerance
        self.maximumSamples = maximumSamples
    }

    public mutating func observe(_ frame: CGRect?) -> FrameReadbackDecision {
        sampleCount += 1
        if let frame, frame.isApproximatelyEqual(to: requestedFrame, tolerance: tolerance) {
            return .verified(frame)
        }
        guard sampleCount >= maximumSamples else { return .pending }
        return frame.map(FrameReadbackDecision.mismatched) ?? .unavailable
    }
}
