import AppKit
import ApplicationServices
import CoreGraphics
import SnapAssistCore

enum WindowSystemError: Error {
    case unavailableWindow
    case frameReadFailed
    case frameWriteFailed
}

final class WindowSystem {
    private final class WindowRecord {
        let id: String
        let processID: pid_t
        let element: AXUIElement

        init(id: String, processID: pid_t, element: AXUIElement) {
            self.id = id
            self.processID = processID
            self.element = element
        }
    }

    var isEnabled = true
    var onWindowsChanged: (() -> Void)?

    private var records: [String: WindowRecord] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        openPrivacyPane("Privacy_ScreenCapture")
    }

    func start() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            workspaceObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshObservers()
                self?.onWindowsChanged?()
            })
        }
        refreshObservers()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        records.removeAll()
    }

    func visibleWindows() -> [WindowDescriptor] {
        guard isEnabled, isAccessibilityTrusted else {
            records.removeAll()
            return []
        }

        let onscreen = onscreenWindowMetadata()
        var nextRecords: [String: WindowRecord] = [:]
        var descriptors: [WindowDescriptor] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            for window in windows(of: appElement) {
                guard let cocoaFrame = frame(of: window),
                      let screen = screen(containing: cocoaFrame),
                      let metadata = bestMetadata(
                        processID: app.processIdentifier,
                        title: stringAttribute(kAXTitleAttribute, of: window) ?? "",
                        frame: cocoaFrame,
                        candidates: onscreen
                      ) else {
                    continue
                }

                let id = windowID(processID: app.processIdentifier, element: window)
                let minimized = boolAttribute(kAXMinimizedAttribute, of: window) ?? false
                let descriptor = WindowDescriptor(
                    id: id,
                    processID: app.processIdentifier,
                    appName: app.localizedName ?? "Unbekannte App",
                    title: stringAttribute(kAXTitleAttribute, of: window) ?? app.localizedName ?? "Fenster",
                    frame: cocoaFrame,
                    screenID: screenID(screen),
                    zOrder: metadata.zOrder,
                    isMinimized: minimized,
                    isMovable: isAttributeSettable(kAXPositionAttribute, of: window),
                    isResizable: isAttributeSettable(kAXSizeAttribute, of: window),
                    isSystemWindow: !isStandardWindow(window)
                )
                descriptors.append(descriptor)
                nextRecords[id] = WindowRecord(id: id, processID: app.processIdentifier, element: window)
            }
        }

        records = nextRecords
        return descriptors.sorted { $0.zOrder < $1.zOrder }
    }

    func focusedWindowID() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window: AXUIElement = attribute(kAXFocusedWindowAttribute, of: appElement) else { return nil }
        return windowID(processID: app.processIdentifier, element: window)
    }

    func frame(for windowID: String) -> CGRect? {
        guard let record = records[windowID] else { return nil }
        return frame(of: record.element)
    }

    @discardableResult
    func setFrame(_ cocoaFrame: CGRect, for windowID: String) -> Bool {
        guard let record = records[windowID] else { return false }
        let axFrame = ScreenCoordinateConverter.cocoaToAX(
            cocoaFrame,
            primaryScreenHeight: primaryScreenHeight
        )
        var point = axFrame.origin
        var size = axFrame.size
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        let sizeResult = AXUIElementSetAttributeValue(record.element, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(record.element, kAXPositionAttribute as CFString, pointValue)
        let finalSizeResult = AXUIElementSetAttributeValue(record.element, kAXSizeAttribute as CFString, sizeValue)
        return sizeResult == .success && positionResult == .success && finalSizeResult == .success
    }

    @discardableResult
    func raise(windowID: String) -> Bool {
        guard let record = records[windowID] else { return false }
        NSRunningApplication(processIdentifier: record.processID)?.activate(options: [])
        return AXUIElementPerformAction(record.element, kAXRaiseAction as CFString) == .success
    }

    func screenFrame(for screenID: String) -> CGRect? {
        NSScreen.screens.first(where: { self.screenID($0) == screenID })?.visibleFrame
    }

    func screenID(containing frame: CGRect) -> String? {
        screen(containing: frame).map(screenID)
    }

    func record(for windowID: String) -> AXUIElement? {
        records[windowID]?.element
    }

    private var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private func refreshObservers() {
        guard isAccessibilityTrusted else { return }
        let runningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        for (pid, observer) in observers where !runningPIDs.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers.removeValue(forKey: pid)
        }

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular
            && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && observers[app.processIdentifier] == nil {
            installObserver(for: app.processIdentifier)
        }
    }

    private func installObserver(for processID: pid_t) {
        var observer: AXObserver?
        let result = AXObserverCreate(processID, windowSystemObserverCallback, &observer)
        guard result == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(processID)
        add(notification: kAXWindowCreatedNotification, element: appElement, observer: observer)
        add(notification: kAXFocusedWindowChangedNotification, element: appElement, observer: observer)
        for window in windows(of: appElement) {
            observe(window: window, with: observer)
        }

        observers[processID] = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    fileprivate func handle(notification: CFString, element: AXUIElement) {
        if notification as String == kAXWindowCreatedNotification as String {
            var processID: pid_t = 0
            AXUIElementGetPid(element, &processID)
            if let observer = observers[processID] {
                observe(window: element, with: observer)
            }
        }
        onWindowsChanged?()
    }

    private func observe(window: AXUIElement, with observer: AXObserver) {
        for notification in [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
        ] {
            add(notification: notification, element: window, observer: observer)
        }
    }

    private func add(notification: String, element: AXUIElement, observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(observer, element, notification as CFString, refcon)
    }

    private func windows(of appElement: AXUIElement) -> [AXUIElement] {
        attribute(kAXWindowsAttribute, of: appElement) ?? []
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(kAXPositionAttribute, of: element),
              let sizeValue: AXValue = attribute(kAXSizeAttribute, of: element) else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return ScreenCoordinateConverter.axToCocoa(
            CGRect(origin: point, size: size),
            primaryScreenHeight: primaryScreenHeight
        )
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
    }

    private func screenID(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }

    private func windowID(processID: pid_t, element: AXUIElement) -> String {
        "\(processID):\(CFHash(element))"
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        guard stringAttribute(kAXRoleAttribute, of: element) == kAXWindowRole else { return false }
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)
        return subrole == nil || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
    }

    private func isAttributeSettable(_ name: String, of element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        attribute(name, of: element)
    }

    private func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        attribute(name, of: element)
    }

    private func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private struct WindowMetadata {
        let processID: pid_t
        let title: String
        let frame: CGRect
        let zOrder: Int
    }

    private func onscreenWindowMetadata() -> [WindowMetadata] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return []
        }

        return info.enumerated().compactMap { index, dictionary in
            guard let ownerPID = dictionary[kCGWindowOwnerPID] as? NSNumber,
                  let boundsValue = dictionary[kCGWindowBounds] else {
                return nil
            }
            let boundsDictionary = boundsValue as! CFDictionary
            guard let axBounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
            return WindowMetadata(
                processID: ownerPID.int32Value,
                title: dictionary[kCGWindowName] as? String ?? "",
                frame: ScreenCoordinateConverter.axToCocoa(
                    axBounds,
                    primaryScreenHeight: primaryScreenHeight
                ),
                zOrder: index
            )
        }
    }

    private func bestMetadata(
        processID: pid_t,
        title: String,
        frame: CGRect,
        candidates: [WindowMetadata]
    ) -> WindowMetadata? {
        candidates.filter { $0.processID == processID }.min { lhs, rhs in
            metadataScore(lhs, title: title, frame: frame) < metadataScore(rhs, title: title, frame: frame)
        }.flatMap { metadataScore($0, title: title, frame: frame) <= 120 ? $0 : nil }
    }

    private func metadataScore(_ metadata: WindowMetadata, title: String, frame: CGRect) -> CGFloat {
        let titlePenalty: CGFloat = metadata.title == title || title.isEmpty || metadata.title.isEmpty ? 0 : 50
        return titlePenalty
            + abs(metadata.frame.minX - frame.minX)
            + abs(metadata.frame.minY - frame.minY)
            + abs(metadata.frame.width - frame.width)
            + abs(metadata.frame.height - frame.height)
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private func windowSystemObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let system = Unmanaged<WindowSystem>.fromOpaque(refcon).takeUnretainedValue()
    system.handle(notification: notification, element: element)
}

private extension CGRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }
}
