import CoreGraphics

public enum ScreenCoordinateConverter {
    public static func axToCocoa(_ frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryScreenHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    public static func cocoaToAX(_ frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryScreenHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

