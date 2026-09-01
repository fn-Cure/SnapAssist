import AppKit
import SnapAssistCore

@MainActor
protocol WindowControlling: AnyObject {
    var onEvent: ((WindowSystemEvent) -> Void)? { get set }
    var isEnabled: Bool { get set }
    var isAccessibilityTrusted: Bool { get }
    var hasScreenRecordingPermission: Bool { get }
    var observerFailureCount: Int { get }
    var degradedObserverCount: Int { get }
    var lastMutationFailureDescription: String? { get }

    func start()
    func stop()
    func refreshAccessibilityState()
    func requestAccessibilityPermission(prompt: Bool) -> Bool
    func requestScreenRecordingPermission()
    func openAccessibilitySettings()
    func visibleWindows() -> [WindowDescriptor]
    func frame(for windowID: String) -> CGRect?
    func setFrame(_ cocoaFrame: CGRect, for windowID: String) async -> WindowMutationResult
    func raise(windowID: String) -> Bool
    func focusedWindowID() -> String?
    func screenFrame(for screenID: String) -> CGRect?
}

@MainActor
protocol ThumbnailProviding: AnyObject {
    func thumbnails(for windows: [WindowDescriptor]) async -> [String: NSImage]
}

extension WindowSystem: WindowControlling {}
extension ThumbnailProvider: ThumbnailProviding {}
