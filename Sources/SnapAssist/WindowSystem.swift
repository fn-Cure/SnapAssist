import AppKit
import ApplicationServices
import CoreGraphics
import OSLog
import SnapAssistCore

enum WindowSystemError: Error {
    case unavailableWindow
    case frameReadFailed
    case frameWriteFailed
}

enum WindowSystemEvent {
    case geometryChanged(windowID: String)
    case inventoryChanged
    case focusChanged
    case environmentChanged
}

enum WindowMutationVerification: String {
    case verified
    case clamped
    case failed
    case unavailable
}

struct WindowMutationResult {
    let requestedFrame: CGRect
    let frameBefore: CGRect?
    let frameAfter: CGRect?
    let sizeErrors: [AXError]
    let positionError: AXError?
    let verification: WindowMutationVerification

    var succeeded: Bool { verification == .verified }
}

@MainActor
final class WindowSystem {
    private final class WindowRecord {
        let id: String
        let cgWindowID: CGWindowID
        let processID: pid_t
        let element: AXUIElement

        init(id: String, cgWindowID: CGWindowID, processID: pid_t, element: AXUIElement) {
            self.id = id
            self.cgWindowID = cgWindowID
            self.processID = processID
            self.element = element
        }
    }

    var isEnabled = true
    var onEvent: ((WindowSystemEvent) -> Void)?

    private var records: [String: WindowRecord] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var lastAccessibilityTrust = AXIsProcessTrusted()
    private let logger = Logger(subsystem: "com.caner.snapassist", category: "WindowSystem")
    private(set) var observerFailureCount = 0
    private(set) var lastMutationFailureDescription: String?

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
        logger.notice("Starting WindowSystem; Accessibility trusted: \(self.isAccessibilityTrusted)")
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            workspaceObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshObservers()
                    self?.onEvent?(.inventoryChanged)
                }
            })
        }
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            workspaceObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.onEvent?(.environmentChanged) }
            })
        }
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onEvent?(.environmentChanged) }
        })
        refreshObservers()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAccessibilityState() }
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
        permissionTimer?.invalidate()
        permissionTimer = nil
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        records.removeAll()
    }

    func refreshAccessibilityState() {
        let trusted = isAccessibilityTrusted
        guard trusted != lastAccessibilityTrust else {
            if trusted && observers.isEmpty { refreshObservers() }
            return
        }
        lastAccessibilityTrust = trusted
        if trusted {
            refreshObservers()
        } else {
            for observer in observers.values {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            observers.removeAll()
            records.removeAll()
        }
        onEvent?(.environmentChanged)
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
            var claimedWindowIDs: Set<CGWindowID> = []
            for window in windows(of: appElement) {
                guard let cocoaFrame = frame(of: window),
                      let screen = screen(containing: cocoaFrame),
                      let metadata = bestMetadata(
                        processID: app.processIdentifier,
                        title: stringAttribute(kAXTitleAttribute, of: window) ?? "",
                        frame: cocoaFrame,
                        candidates: onscreen.filter { !claimedWindowIDs.contains($0.windowID) }
                      ) else {
                    continue
                }

                claimedWindowIDs.insert(metadata.windowID)
                let id = windowID(processID: app.processIdentifier, cgWindowID: metadata.windowID)
                let minimized = boolAttribute(kAXMinimizedAttribute, of: window) ?? false
                let modal = boolAttribute(kAXModalAttribute, of: window) ?? false
                let fullScreen = boolAttribute("AXFullScreen", of: window) ?? false
                let descriptor = WindowDescriptor(
                    id: id,
                    cgWindowID: metadata.windowID,
                    processID: app.processIdentifier,
                    appName: app.localizedName ?? "Unbekannte App",
                    title: stringAttribute(kAXTitleAttribute, of: window) ?? app.localizedName ?? "Fenster",
                    frame: cocoaFrame,
                    screenID: screenID(screen),
                    zOrder: metadata.zOrder,
                    isMinimized: minimized,
                    isMovable: isAttributeSettable(kAXPositionAttribute, of: window),
                    isResizable: isAttributeSettable(kAXSizeAttribute, of: window),
                    isSystemWindow: !isStandardWindow(window),
                    isModal: modal,
                    isFullScreen: fullScreen
                )
                descriptors.append(descriptor)
                nextRecords[id] = WindowRecord(
                    id: id,
                    cgWindowID: metadata.windowID,
                    processID: app.processIdentifier,
                    element: window
                )
            }
        }

        records = nextRecords
        logger.debug("Visible movable windows: \(descriptors.count)")
        return descriptors.sorted { $0.zOrder < $1.zOrder }
    }

    func focusedWindowID() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window: AXUIElement = attribute(kAXFocusedWindowAttribute, of: appElement) else { return nil }
        if let record = records.values.first(where: {
            $0.processID == app.processIdentifier && CFEqual($0.element, window)
        }) {
            return record.id
        }
        return resolveWindowID(processID: app.processIdentifier, element: window)
    }

    func frame(for windowID: String) -> CGRect? {
        guard let record = records[windowID] else { return nil }
        return frame(of: record.element)
    }

    @discardableResult
    func setFrame(_ cocoaFrame: CGRect, for windowID: String) -> WindowMutationResult {
        guard let record = records[windowID] else {
            let result = WindowMutationResult(
                requestedFrame: cocoaFrame,
                frameBefore: nil,
                frameAfter: nil,
                sizeErrors: [],
                positionError: nil,
                verification: .unavailable
            )
            lastMutationFailureDescription = "Fenster ist nicht mehr verfügbar"
            return result
        }
        let frameBefore = frame(of: record.element)
        _ = AXUIElementSetMessagingTimeout(record.element, 0.25)
        let axFrame = ScreenCoordinateConverter.cocoaToAX(
            cocoaFrame,
            primaryScreenHeight: primaryScreenHeight
        )
        var point = axFrame.origin
        var size = axFrame.size
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            let result = WindowMutationResult(
                requestedFrame: cocoaFrame,
                frameBefore: frameBefore,
                frameAfter: frameBefore,
                sizeErrors: [.illegalArgument],
                positionError: .illegalArgument,
                verification: .failed
            )
            lastMutationFailureDescription = "AX-Werte konnten nicht erzeugt werden"
            return result
        }

        var sizeErrors: [AXError] = []
        var positionError: AXError?
        if frameBefore?.size.isApproximatelyEqual(to: cocoaFrame.size, tolerance: 1) != true {
            let result = AXUIElementSetAttributeValue(record.element, kAXSizeAttribute as CFString, sizeValue)
            if result != .success { sizeErrors.append(result) }
        }
        if frameBefore?.origin.isApproximatelyEqual(to: cocoaFrame.origin, tolerance: 1) != true {
            let result = AXUIElementSetAttributeValue(record.element, kAXPositionAttribute as CFString, pointValue)
            if result != .success { positionError = result }
        }
        let finalSizeResult = AXUIElementSetAttributeValue(record.element, kAXSizeAttribute as CFString, sizeValue)
        if finalSizeResult != .success { sizeErrors.append(finalSizeResult) }

        let frameAfter = frame(of: record.element)
        let verification: WindowMutationVerification
        if frameAfter?.isApproximatelyEqual(to: cocoaFrame, tolerance: 4) == true {
            verification = .verified
            lastMutationFailureDescription = nil
        } else if frameAfter != nil && sizeErrors.isEmpty && positionError == nil {
            verification = .clamped
            lastMutationFailureDescription = "Ziel-App hat die Fenstergröße begrenzt"
        } else {
            verification = .failed
            lastMutationFailureDescription = "AX-Frameänderung fehlgeschlagen"
        }
        return WindowMutationResult(
            requestedFrame: cocoaFrame,
            frameBefore: frameBefore,
            frameAfter: frameAfter,
            sizeErrors: sizeErrors,
            positionError: positionError,
            verification: verification
        )
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
        guard isAccessibilityTrusted else {
            logger.error("Cannot install AX observers because Accessibility is not trusted")
            return
        }
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
        logger.debug("Active AX observers: \(self.observers.count)")
    }

    private func installObserver(for processID: pid_t) {
        var observer: AXObserver?
        let result = AXObserverCreate(processID, windowSystemObserverCallback, &observer)
        guard result == .success, let observer else {
            logger.error("AXObserverCreate failed for pid \(processID) with code \(result.rawValue)")
            return
        }

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
        let notificationName = notification as String
        logger.debug("Received AX notification: \(notificationName, privacy: .public)")
        if notificationName == kAXWindowCreatedNotification as String {
            var processID: pid_t = 0
            AXUIElementGetPid(element, &processID)
            if let observer = observers[processID] {
                observe(window: element, with: observer)
            }
            onEvent?(.inventoryChanged)
            return
        }

        if notificationName == kAXMovedNotification as String
            || notificationName == kAXResizedNotification as String {
            var processID: pid_t = 0
            AXUIElementGetPid(element, &processID)
            guard let windowID = resolveWindowID(processID: processID, element: element) else {
                onEvent?(.inventoryChanged)
                return
            }
            onEvent?(.geometryChanged(windowID: windowID))
        } else if notificationName == kAXFocusedWindowChangedNotification as String {
            onEvent?(.focusChanged)
        } else {
            onEvent?(.inventoryChanged)
        }
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
        let result = AXObserverAddNotification(observer, element, notification as CFString, refcon)
        if result != .success && result != .notificationAlreadyRegistered && result != .notificationUnsupported {
            observerFailureCount += 1
            logger.error("AXObserverAddNotification failed for \(notification, privacy: .public) with code \(result.rawValue)")
        }
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

    private func windowID(processID: pid_t, cgWindowID: CGWindowID) -> String {
        "\(processID):\(cgWindowID)"
    }

    private func resolveWindowID(processID: pid_t, element: AXUIElement) -> String? {
        if let record = records.values.first(where: {
            $0.processID == processID && CFEqual($0.element, element)
        }) {
            return record.id
        }
        guard let frame = frame(of: element),
              let metadata = bestMetadata(
                processID: processID,
                title: stringAttribute(kAXTitleAttribute, of: element) ?? "",
                frame: frame,
                candidates: onscreenWindowMetadata()
              ) else {
            return nil
        }
        let id = windowID(processID: processID, cgWindowID: metadata.windowID)
        records[id] = WindowRecord(
            id: id,
            cgWindowID: metadata.windowID,
            processID: processID,
            element: element
        )
        return id
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        guard stringAttribute(kAXRoleAttribute, of: element) == kAXWindowRole else { return false }
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)
        return subrole == kAXStandardWindowSubrole
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
        let windowID: CGWindowID
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
                  let windowNumber = dictionary[kCGWindowNumber] as? NSNumber,
                  let layer = dictionary[kCGWindowLayer] as? NSNumber,
                  layer.intValue == 0,
                  let boundsValue = dictionary[kCGWindowBounds] else {
                return nil
            }
            let boundsDictionary = boundsValue as! CFDictionary
            guard let axBounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
            return WindowMetadata(
                windowID: CGWindowID(windowNumber.uint32Value),
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
        let processCandidates = candidates.filter { $0.processID == processID }
        let scored: [(metadata: WindowMetadata, score: CGFloat)] = processCandidates.map { candidate in
            (candidate, metadataScore(candidate, title: title, frame: frame))
        }
        let ranked = scored.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.metadata.zOrder < rhs.metadata.zOrder }
            return lhs.score < rhs.score
        }
        guard let best = ranked.first, best.score <= 120 else { return nil }
        if ranked.count > 1, ranked[1].score - best.score < 4 {
            logger.debug("Skipping ambiguous AX/CG window match for pid \(processID)")
            return nil
        }
        return best.metadata
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
    Task { @MainActor in
        system.handle(notification: notification, element: element)
    }
}

private extension CGRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }
}
