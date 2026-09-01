import AppKit
import CoreGraphics
import ScreenCaptureKit
import SnapAssistCore

@MainActor
final class ThumbnailProvider {
    func thumbnails(for windows: [WindowDescriptor]) async -> [String: NSImage] {
        guard CGPreflightScreenCaptureAccess(), !windows.isEmpty else { return [:] }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
            var result: [String: NSImage] = [:]

            for descriptor in windows {
                if Task.isCancelled { return result }
                guard let captureWindow = bestMatch(for: descriptor, in: content.windows) else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: captureWindow)
                let configuration = SCStreamConfiguration()
                let targetWidth = 360
                let aspectRatio = max(0.3, captureWindow.frame.height / max(captureWindow.frame.width, 1))
                configuration.width = targetWidth
                configuration.height = min(300, max(120, Int(CGFloat(targetWidth) * aspectRatio)))
                configuration.scalesToFit = true
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = false

                if let image = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                ) {
                    result[descriptor.id] = NSImage(
                        cgImage: image,
                        size: NSSize(width: image.width, height: image.height)
                    )
                }
            }

            return result
        } catch {
            return [:]
        }
    }

    private func bestMatch(for descriptor: WindowDescriptor, in windows: [SCWindow]) -> SCWindow? {
        if let cgWindowID = descriptor.cgWindowID {
            return windows.first { $0.windowID == cgWindowID }
        }
        return windows.filter {
            $0.owningApplication?.processID == descriptor.processID
        }.min {
            score($0, descriptor: descriptor) < score($1, descriptor: descriptor)
        }.flatMap { score($0, descriptor: descriptor) <= 80 ? $0 : nil }
    }

    private func score(_ window: SCWindow, descriptor: WindowDescriptor) -> CGFloat {
        let titlePenalty: CGFloat
        if window.title == descriptor.title || window.title == nil || descriptor.title.isEmpty {
            titlePenalty = 0
        } else {
            titlePenalty = 100
        }

        let direct = frameDistance(window.frame, descriptor.frame)
        let converted = frameDistance(
            ScreenCoordinateConverter.axToCocoa(
                window.frame,
                primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0
            ),
            descriptor.frame
        )
        return titlePenalty + min(direct, converted)
    }

    private func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX)
            + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }
}
