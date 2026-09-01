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
    let attemptCount: Int
    let rolledBack: Bool

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
    private var geometryPollTimer: DispatchSourceTimer?
    private var lastAccessibilityTrust = AXIsProcessTrusted()
    private var lastScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    private var observerRetryWorkItems: [pid_t: DispatchWorkItem] = [:]
    private var observerRetryAttempts: [pid_t: Int] = [:]
    private var degradedObserverPIDs: Set<pid_t> = []
    private var lastPolledCGFrames: [String: CGRect] = [:]
    private let logger = Logger(subsystem: "com.caner.snapassist", category: "WindowSystem")
    private let diagnostics = DiagnosticsStore.shared
    private(set) var observerFailureCount = 0
    private(set) var lastMutationFailureDescription: String?

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var degradedObserverCount: Int { degradedObserverPIDs.count }

    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
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
                    self?.pollKnownWindowGeometry()
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
        _ = visibleWindows()
        seedKnownWindowGeometry()
        updateFocusedPollTimer()
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
        geometryPollTimer?.cancel()
        geometryPollTimer = nil
        observerRetryWorkItems.values.forEach { $0.cancel() }
        observerRetryWorkItems.removeAll()
        observerRetryAttempts.removeAll()
        degradedObserverPIDs.removeAll()
        lastPolledCGFrames.removeAll()
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        records.removeAll()
    }

    func refreshAccessibilityState() {
        let trusted = isAccessibilityTrusted
        let screenRecordingGranted = hasScreenRecordingPermission
        let trustChanged = trusted != lastAccessibilityTrust
        let screenRecordingChanged = screenRecordingGranted != lastScreenRecordingPermission
        guard trustChanged || screenRecordingChanged else {
            if trusted && observers.isEmpty { refreshObservers() }
            return
        }
        lastAccessibilityTrust = trusted
        lastScreenRecordingPermission = screenRecordingGranted
        if trustChanged {
            if trusted {
                refreshObservers()
                _ = visibleWindows()
                seedKnownWindowGeometry()
            } else {
                for observer in observers.values {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                }
                observers.removeAll()
                records.removeAll()
                lastPolledCGFrames.removeAll()
            }
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
        if let record = records[windowID] {
            return frame(of: record.element)
        }
        return onscreenWindowMetadata().first { metadata in
            self.windowID(processID: metadata.processID, cgWindowID: metadata.windowID) == windowID
        }?.frame
    }

    @discardableResult
    func setFrame(_ cocoaFrame: CGRect, for windowID: String) async -> WindowMutationResult {
        guard let record = records[windowID] else {
            let result = WindowMutationResult(
                requestedFrame: cocoaFrame,
                frameBefore: nil,
                frameAfter: nil,
                sizeErrors: [],
                positionError: nil,
                verification: .unavailable,
                attemptCount: 0,
                rolledBack: false
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
                verification: .failed,
                attemptCount: 0,
                rolledBack: false
            )
            lastMutationFailureDescription = "AX-Werte konnten nicht erzeugt werden"
            return result
        }

        var sizeErrors: [AXError] = []
        var positionError: AXError?
        var attemptCount = 0

        let firstWrite = writeFrame(
            element: record.element,
            pointValue: pointValue,
            sizeValue: sizeValue,
            order: .positionSizePosition
        )
        attemptCount += 1
        sizeErrors.append(contentsOf: firstWrite.sizeErrors)
        positionError = firstWrite.positionError

        var readback = await waitForFrame(
            cocoaFrame,
            element: record.element,
            maximumSamples: 8,
            intervalNanoseconds: 30_000_000
        )

        if Task.isCancelled {
            let rolledBack = await restoreFrame(frameBefore, element: record.element)
            return mutationResult(
                requestedFrame: cocoaFrame,
                frameBefore: frameBefore,
                readback: readback,
                sizeErrors: sizeErrors,
                positionError: positionError,
                attemptCount: attemptCount,
                rolledBack: rolledBack,
                processID: record.processID,
                cgWindowID: record.cgWindowID
            )
        }

        if case .verified = readback {
            return mutationResult(
                requestedFrame: cocoaFrame,
                frameBefore: frameBefore,
                readback: readback,
                sizeErrors: sizeErrors,
                positionError: positionError,
                attemptCount: attemptCount,
                rolledBack: false,
                processID: record.processID,
                cgWindowID: record.cgWindowID
            )
        }

        let secondWrite = writeFrame(
            element: record.element,
            pointValue: pointValue,
            sizeValue: sizeValue,
            order: .sizePositionSize
        )
        attemptCount += 1
        sizeErrors.append(contentsOf: secondWrite.sizeErrors)
        if secondWrite.positionError != nil { positionError = secondWrite.positionError }
        readback = await waitForFrame(
            cocoaFrame,
            element: record.element,
            maximumSamples: 8,
            intervalNanoseconds: 30_000_000
        )

        if case .verified = readback {
            return mutationResult(
                requestedFrame: cocoaFrame,
                frameBefore: frameBefore,
                readback: readback,
                sizeErrors: sizeErrors,
                positionError: positionError,
                attemptCount: attemptCount,
                rolledBack: false,
                processID: record.processID,
                cgWindowID: record.cgWindowID
            )
        }

        var rolledBack = false
        if let frameBefore,
           let currentFrame = frame(of: record.element),
           !currentFrame.isApproximatelyEqual(to: frameBefore, tolerance: 4) {
            rolledBack = await restoreFrame(frameBefore, element: record.element)
        }

        return mutationResult(
            requestedFrame: cocoaFrame,
            frameBefore: frameBefore,
            readback: readback,
            sizeErrors: sizeErrors,
            positionError: positionError,
            attemptCount: attemptCount,
            rolledBack: rolledBack,
            processID: record.processID,
            cgWindowID: record.cgWindowID
        )
    }

    private enum FrameWriteOrder {
        case positionSizePosition
        case sizePositionSize
    }

    private func writeFrame(
        element: AXUIElement,
        pointValue: AXValue,
        sizeValue: AXValue,
        order: FrameWriteOrder
    ) -> (sizeErrors: [AXError], positionError: AXError?) {
        let attributes: [(String, AXValue)]
        switch order {
        case .positionSizePosition:
            attributes = [
                (kAXPositionAttribute, pointValue),
                (kAXSizeAttribute, sizeValue),
                (kAXPositionAttribute, pointValue),
            ]
        case .sizePositionSize:
            attributes = [
                (kAXSizeAttribute, sizeValue),
                (kAXPositionAttribute, pointValue),
                (kAXSizeAttribute, sizeValue),
            ]
        }

        var sizeErrors: [AXError] = []
        var positionError: AXError?
        for (attribute, value) in attributes {
            let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
            guard result != .success else { continue }
            if attribute == kAXSizeAttribute {
                sizeErrors.append(result)
            } else {
                positionError = result
            }
        }
        return (sizeErrors, positionError)
    }

    private func waitForFrame(
        _ requestedFrame: CGRect,
        element: AXUIElement,
        maximumSamples: Int,
        intervalNanoseconds: UInt64,
        ignoreCancellation: Bool = false
    ) async -> FrameReadbackDecision {
        var verifier = FrameReadbackVerifier(
            requestedFrame: requestedFrame,
            tolerance: 4,
            maximumSamples: maximumSamples
        )
        for index in 0..<maximumSamples {
            guard ignoreCancellation || !Task.isCancelled else { return .unavailable }
            let decision = verifier.observe(frame(of: element))
            if decision != .pending { return decision }
            if index + 1 < maximumSamples {
                do {
                    if ignoreCancellation {
                        await withCheckedContinuation { continuation in
                            DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(intervalNanoseconds))) {
                                continuation.resume()
                            }
                        }
                    } else {
                        try await Task.sleep(nanoseconds: intervalNanoseconds)
                    }
                } catch {
                    return .unavailable
                }
            }
        }
        return .unavailable
    }

    private func restoreFrame(_ cocoaFrame: CGRect?, element: AXUIElement) async -> Bool {
        guard let cocoaFrame else { return false }
        let axFrame = ScreenCoordinateConverter.cocoaToAX(
            cocoaFrame,
            primaryScreenHeight: primaryScreenHeight
        )
        var point = axFrame.origin
        var size = axFrame.size
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        _ = writeFrame(
            element: element,
            pointValue: pointValue,
            sizeValue: sizeValue,
            order: .positionSizePosition
        )
        let readback = await waitForFrame(
            cocoaFrame,
            element: element,
            maximumSamples: 6,
            intervalNanoseconds: 30_000_000,
            ignoreCancellation: true
        )
        if case .verified = readback { return true }
        return false
    }

    private func mutationResult(
        requestedFrame: CGRect,
        frameBefore: CGRect?,
        readback: FrameReadbackDecision,
        sizeErrors: [AXError],
        positionError: AXError?,
        attemptCount: Int,
        rolledBack: Bool,
        processID: pid_t,
        cgWindowID: CGWindowID
    ) -> WindowMutationResult {
        let observedFrameAfter: CGRect?
        let verification: WindowMutationVerification
        switch readback {
        case let .verified(frame):
            observedFrameAfter = frame
            verification = .verified
            lastMutationFailureDescription = nil
        case let .mismatched(frame):
            observedFrameAfter = frame
            verification = sizeErrors.isEmpty && positionError == nil ? .clamped : .failed
            lastMutationFailureDescription = "Ziel-App hat Position oder Größe nicht übernommen"
        case .unavailable:
            observedFrameAfter = nil
            verification = .unavailable
            lastMutationFailureDescription = "Fenster-Frame konnte nicht verifiziert werden"
        case .pending:
            observedFrameAfter = nil
            verification = .failed
            lastMutationFailureDescription = "Fenster-Frame blieb instabil"
        }
        let frameAfter = rolledBack ? frameBefore : observedFrameAfter

        logger.notice(
            "AX mutation pid=\(processID) cgWindowID=\(cgWindowID) verification=\(verification.rawValue, privacy: .public) attempts=\(attemptCount) rolledBack=\(rolledBack) before=\(String(describing: frameBefore), privacy: .public) requested=\(String(describing: requestedFrame), privacy: .public) after=\(String(describing: frameAfter), privacy: .public) sizeErrors=\(sizeErrors.map(\.rawValue), privacy: .public) positionError=\(String(describing: positionError?.rawValue), privacy: .public)"
        )
        diagnostics.record(
            category: "mutation",
            "pid=\(processID), window=\(cgWindowID), verification=\(verification.rawValue), attempts=\(attemptCount), rolledBack=\(rolledBack)"
        )

        return WindowMutationResult(
            requestedFrame: requestedFrame,
            frameBefore: frameBefore,
            frameAfter: frameAfter,
            sizeErrors: sizeErrors,
            positionError: positionError,
            verification: verification,
            attemptCount: attemptCount,
            rolledBack: rolledBack
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
            degradedObserverPIDs.remove(pid)
            observerRetryWorkItems.removeValue(forKey: pid)?.cancel()
            observerRetryAttempts.removeValue(forKey: pid)
        }

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular
            && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && observers[app.processIdentifier] == nil {
            installObserver(for: app.processIdentifier)
        }
        logger.debug("Active AX observers: \(self.observers.count)")
        updateFocusedPollTimer()
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

    fileprivate func handle(notification notificationName: String, element: AXUIElement) {
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
            degradedObserverPIDs.remove(processID)
            observerRetryAttempts.removeValue(forKey: processID)
            updateFocusedPollTimer()
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
        if result == .invalidUIElement || result == .cannotComplete {
            var processID: pid_t = 0
            AXUIElementGetPid(element, &processID)
            let inserted = degradedObserverPIDs.insert(processID).inserted
            logger.debug("Deferring AX observer registration for transient error \(result.rawValue) in pid \(processID)")
            if inserted {
                diagnostics.record(category: "observer", "pid=\(processID) entered fallback after AX error \(result.rawValue)")
            }
            scheduleObserverRetry(for: processID)
            updateFocusedPollTimer()
            return
        }
        if result != .success && result != .notificationAlreadyRegistered && result != .notificationUnsupported {
            observerFailureCount += 1
            logger.error("AXObserverAddNotification failed for \(notification, privacy: .public) with code \(result.rawValue)")
            diagnostics.record(category: "observer", "registration failed with AX error \(result.rawValue)")
        }
    }

    private func scheduleObserverRetry(for processID: pid_t) {
        guard processID > 0,
              observerRetryWorkItems[processID] == nil,
              observerRetryAttempts[processID, default: 0] < 3 else { return }
        let attempt = observerRetryAttempts[processID, default: 0] + 1
        observerRetryAttempts[processID] = attempt
        var item: DispatchWorkItem!
        item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.observerRetryWorkItems.removeValue(forKey: processID)
            guard !item.isCancelled, let observer = self.observers[processID] else { return }
            let appElement = AXUIElementCreateApplication(processID)
            self.add(notification: kAXWindowCreatedNotification, element: appElement, observer: observer)
            self.add(notification: kAXFocusedWindowChangedNotification, element: appElement, observer: observer)
            for window in self.windows(of: appElement) {
                self.observe(window: window, with: observer)
            }
        }
        observerRetryWorkItems[processID] = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.25 * Double(attempt),
            execute: item
        )
    }

    private func updateFocusedPollTimer() {
        guard geometryPollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.pollKnownWindowGeometry() }
        geometryPollTimer = timer
        timer.resume()
        logger.notice("Started CG geometry fallback polling")
    }

    private func seedKnownWindowGeometry() {
        lastPolledCGFrames = Dictionary(uniqueKeysWithValues: onscreenWindowMetadata().compactMap { item in
            guard item.processID != ProcessInfo.processInfo.processIdentifier,
                  item.frame.width >= 80,
                  item.frame.height >= 60 else { return nil }
            let id = windowID(processID: item.processID, cgWindowID: item.windowID)
            return (id, item.frame)
        })
    }

    private func pollKnownWindowGeometry() {
        guard isEnabled, isAccessibilityTrusted else { return }
        let metadata = onscreenWindowMetadata()
        let currentFrames = Dictionary(uniqueKeysWithValues: metadata.compactMap { item -> (String, CGRect)? in
            guard item.processID != ProcessInfo.processInfo.processIdentifier,
                  item.frame.width >= 80,
                  item.frame.height >= 60 else { return nil }
            let id = windowID(processID: item.processID, cgWindowID: item.windowID)
            return (id, item.frame)
        })
        let previousFrames = lastPolledCGFrames
        lastPolledCGFrames = currentFrames

        let inventoryChanged = previousFrames.keys.contains { currentFrames[$0] == nil }
        for (windowID, currentFrame) in currentFrames {
            guard let previousFrame = previousFrames[windowID] else { continue }
            guard !previousFrame.isApproximatelyEqual(to: currentFrame, tolerance: 2) else { continue }
            logger.debug("CG polling detected geometry change window=\(windowID, privacy: .public) from=\(String(describing: previousFrame), privacy: .public) to=\(String(describing: currentFrame), privacy: .public)")
            onEvent?(.geometryChanged(windowID: windowID))
        }
        if inventoryChanged { onEvent?(.inventoryChanged) }
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
            guard let boundsDictionary = boundsValue as? NSDictionary else { return nil }
            guard let axBounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                return nil
            }
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
    let payload = WindowSystemObserverPayload(
        system: Unmanaged<WindowSystem>.fromOpaque(refcon).takeUnretainedValue(),
        element: element,
        notification: notification as String
    )
    Task { @MainActor in
        payload.system.handle(notification: payload.notification, element: payload.element)
    }
}

private struct WindowSystemObserverPayload: @unchecked Sendable {
    let system: WindowSystem
    let element: AXUIElement
    let notification: String
}

private extension CGRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }
}
