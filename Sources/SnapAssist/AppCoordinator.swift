import AppKit
import OSLog
import SnapAssistCore

@MainActor
final class AppCoordinator {
    let windowSystem: WindowSystem

    private let thumbnailProvider: ThumbnailProvider
    private let pickerController: PickerController
    private var runtimeState = SnapRuntimeState()
    private var mutationLedger = WindowMutationLedger()
    private var pendingDetections: [String: DispatchWorkItem] = [:]
    private var thumbnailTask: Task<Void, Never>?
    private var placementTask: Task<Void, Never>?
    private var activeMutationWindowIDs: Set<String> = []
    private var thumbnailCache: [String: NSImage] = [:]
    private let logger = Logger(subsystem: "com.caner.snapassist", category: "Coordinator")
    private let diagnostics = DiagnosticsStore.shared
    private lazy var linkedResizeController = LinkedResizeController(
        windowSystem: windowSystem,
        groupsProvider: { [weak self] in self?.runtimeState.groups ?? [:] },
        mutationRegistered: { [weak self] operationID, windowID, frame in
            self?.mutationLedger.register(
                operationID: operationID,
                windowID: windowID,
                expectedFrame: frame,
                expiresAt: ProcessInfo.processInfo.systemUptime + 1.0
            )
        },
        shouldIgnore: { [weak self] in self?.pickerController.isVisible ?? true },
        onVerifiedFrames: { [weak self] screenID, frames in
            self?.runtimeState.updateVerifiedFrames(screenID: screenID, frames: frames)
        },
        onFailure: { [weak self] in self?.invalidateAll(reason: "linked resize failed") }
    )

    var groups: [String: LayoutGroup] { runtimeState.groups }
    var linkedResizeMonitorInstalled: Bool { linkedResizeController.monitorInstalled }

    var isEnabled: Bool {
        get { windowSystem.isEnabled }
        set {
            windowSystem.isEnabled = newValue
            if newValue {
                linkedResizeController.isEnabled = linkedResizingEnabled
            } else {
                invalidateAll(reason: "paused")
            }
        }
    }

    var linkedResizingEnabled = false {
        didSet {
            linkedResizeController.isEnabled = linkedResizingEnabled && isEnabled
        }
    }

    init(
        windowSystem: WindowSystem,
        thumbnailProvider: ThumbnailProvider,
        pickerController: PickerController
    ) {
        self.windowSystem = windowSystem
        self.thumbnailProvider = thumbnailProvider
        self.pickerController = pickerController
        pickerController.onSelect = { [weak self] windowID, zoneID in
            self?.place(windowID: windowID, into: zoneID)
        }
        pickerController.onCancel = { [weak self] in
            guard let self else { return }
            self.thumbnailTask?.cancel()
            self.thumbnailTask = nil
            self.runtimeState.cancelSession(removeIncompleteGroup: true)
        }
    }

    convenience init() {
        self.init(
            windowSystem: WindowSystem(),
            thumbnailProvider: ThumbnailProvider(),
            pickerController: PickerController()
        )
    }

    func start() {
        windowSystem.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        windowSystem.start()
        linkedResizeController.isEnabled = linkedResizingEnabled
    }

    func stop() {
        invalidateAll(reason: "stopping")
        linkedResizeController.stop()
        windowSystem.stop()
    }

    private func handle(_ event: WindowSystemEvent) {
        guard isEnabled else { return }
        switch event {
        case let .geometryChanged(windowID):
            if activeMutationWindowIDs.contains(windowID) { return }
            if let actualFrame = windowSystem.frame(for: windowID),
               case .programmatic = mutationLedger.classify(
                windowID: windowID,
                actualFrame: actualFrame,
                at: ProcessInfo.processInfo.systemUptime
               ) {
                return
            }
            invalidate(windowID: windowID, dismissPicker: true)
            scheduleSnapDetection(windowID: windowID)
        case .inventoryChanged:
            reconcileRuntime()
        case .environmentChanged:
            invalidateAll(reason: "environment changed")
        case .focusChanged:
            break
        }
    }

    private func scheduleSnapDetection(windowID: String) {
        pendingDetections[windowID]?.cancel()
        var item: DispatchWorkItem!
        item = DispatchWorkItem { [weak self] in
            guard let self, !item.isCancelled,
                  let firstFrame = self.windowSystem.frame(for: windowID) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self, self.pendingDetections[windowID] === item else { return }
                defer { self.pendingDetections.removeValue(forKey: windowID) }
                guard !item.isCancelled,
                      let settledFrame = self.windowSystem.frame(for: windowID),
                      firstFrame.isApproximatelyEqual(to: settledFrame, tolerance: 2) else { return }
                self.detectSnap(windowID: windowID)
            }
        }
        pendingDetections[windowID] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    private func detectSnap(windowID: String) {
        let windows = windowSystem.visibleWindows()
        guard let trigger = windows.first(where: { $0.id == windowID }) else {
            invalidate(windowID: windowID, dismissPicker: true)
            logger.notice("Discarded geometry event: stable window \(windowID, privacy: .public) missing from AX/CG catalog of \(windows.count) window(s)")
            diagnostics.record(category: "detection", "discarded: stable ID missing from correlated catalog")
            return
        }
        guard let screenFrame = windowSystem.screenFrame(for: trigger.screenID) else {
            invalidate(windowID: windowID, dismissPicker: true)
            logger.notice("Discarded geometry event: display \(trigger.screenID, privacy: .public) unavailable for window \(windowID, privacy: .public)")
            diagnostics.record(category: "detection", "discarded: display unavailable")
            return
        }
        guard let session = LayoutStateBuilder.buildSession(
                trigger: trigger,
                windowsOnTargetScreen: windows.filter { $0.screenID == trigger.screenID },
                allVisibleWindows: windows,
                screenFrame: screenFrame,
                ownProcessID: ProcessInfo.processInfo.processIdentifier
              ) else {
            invalidate(windowID: windowID, dismissPicker: true)
            logger.notice("Discarded geometry event: frame=\(String(describing: trigger.frame), privacy: .public) does not match a supported layout on screen=\(String(describing: screenFrame), privacy: .public)")
            diagnostics.record(category: "detection", "discarded: geometry does not match supported layout")
            return
        }

        logger.notice("Detected \(session.group.layout.kind.rawValue, privacy: .public) snap with \(session.emptyZoneIDs.count) empty zones and \(session.candidates.count) candidates")
        diagnostics.record(
            category: "detection",
            "layout=\(session.group.layout.kind.rawValue), emptyZones=\(session.emptyZoneIDs.count), candidates=\(session.candidates.count)"
        )
        let generation = runtimeState.install(session)
        thumbnailTask?.cancel()
        thumbnailCache = thumbnailCache.filter { id, _ in session.candidates.contains(where: { $0.id == id }) }

        guard !session.emptyZoneIDs.isEmpty, !session.candidates.isEmpty else {
            pickerController.dismiss(notify: false)
            runtimeState.cancelSession(removeIncompleteGroup: true)
            return
        }

        pickerController.present(session: session, thumbnails: thumbnailCache)
        loadThumbnails(for: session, generation: generation)
    }

    private func loadThumbnails(for session: AssistSession, generation: UInt64) {
        let missingCandidates = session.candidates.filter { thumbnailCache[$0.id] == nil }
        guard !missingCandidates.isEmpty else { return }
        thumbnailTask?.cancel()
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            let thumbnails = await thumbnailProvider.thumbnails(for: missingCandidates)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.runtimeState.isCurrentPresentation(generation),
                      self.runtimeState.activeSession?.group == session.group else { return }
                self.thumbnailCache.merge(thumbnails) { _, new in new }
                self.pickerController.updateThumbnails(thumbnails)
            }
        }
    }

    private func place(windowID: String, into zoneID: Int) {
        guard let originalSession = runtimeState.activeSession else { return }
        var stagedSession = originalSession
        guard
              let targetFrame = stagedSession.place(windowID: windowID, into: zoneID) else {
            return
        }

        pickerController.dismiss(notify: false)
        placementTask?.cancel()
        placementTask = Task { [weak self] in
            guard let self else { return }
            defer { self.placementTask = nil }
            await self.performPlacement(
                originalSession: originalSession,
                stagedSession: stagedSession,
                windowID: windowID,
                targetFrame: targetFrame
            )
        }
    }

    private func performPlacement(
        originalSession: AssistSession,
        stagedSession initialStagedSession: AssistSession,
        windowID: String,
        targetFrame: CGRect
    ) async {
        var stagedSession = initialStagedSession

        let operationID = UUID()
        mutationLedger.register(
            operationID: operationID,
            windowID: windowID,
            expectedFrame: targetFrame,
            expiresAt: ProcessInfo.processInfo.systemUptime + 2.0
        )
        activeMutationWindowIDs.insert(windowID)
        let result = await windowSystem.setFrame(targetFrame, for: windowID)
        activeMutationWindowIDs.remove(windowID)
        guard result.succeeded, let verifiedFrame = result.frameAfter else {
            diagnostics.record(
                category: "mutation",
                "placement failed: verification=\(result.verification.rawValue), attempts=\(result.attemptCount), rolledBack=\(result.rolledBack)"
            )
            mutationLedger.cancel(windowID: windowID)
            if runtimeState.activeSession == originalSession {
                pickerController.present(session: originalSession, thumbnails: thumbnailCache)
                pickerController.showError(
                    result.rolledBack
                        ? "Fenster konnte nicht platziert werden und wurde zurückgesetzt."
                        : "Diese App hat die Fensterposition nicht vollständig übernommen."
                )
            } else {
                invalidateAll(reason: "picker placement failed verification")
            }
            return
        }

        guard runtimeState.activeSession == originalSession else {
            mutationLedger.cancel(windowID: windowID)
            if let frameBefore = result.frameBefore {
                activeMutationWindowIDs.insert(windowID)
                _ = await windowSystem.setFrame(frameBefore, for: windowID)
                activeMutationWindowIDs.remove(windowID)
            }
            invalidateAll(reason: "picker session changed during placement")
            return
        }

        stagedSession.group.verifiedFrames[windowID] = verifiedFrame
        diagnostics.record(category: "mutation", "placement verified in \(result.attemptCount) attempt(s)")
        let generation = runtimeState.install(stagedSession)
        _ = windowSystem.raise(windowID: windowID)

        if stagedSession.emptyZoneIDs.isEmpty || stagedSession.candidates.isEmpty {
            pickerController.dismiss(notify: false)
            runtimeState.cancelSession(removeIncompleteGroup: true)
            thumbnailTask?.cancel()
            thumbnailTask = nil
        } else {
            thumbnailCache = thumbnailCache.filter { id, _ in stagedSession.candidates.contains(where: { $0.id == id }) }
            pickerController.present(session: stagedSession, thumbnails: thumbnailCache)
            loadThumbnails(for: stagedSession, generation: generation)
        }
    }

    private func reconcileRuntime() {
        let windows = windowSystem.visibleWindows()
        let previousSession = runtimeState.activeSession
        runtimeState.reconcile(with: windows)
        guard let session = runtimeState.activeSession else {
            if previousSession != nil {
                thumbnailTask?.cancel()
                thumbnailTask = nil
                pickerController.dismiss(notify: false)
            }
            return
        }
        if previousSession != session, pickerController.isVisible {
            pickerController.present(session: session, thumbnails: thumbnailCache)
        }
    }

    private func invalidate(windowID: String, dismissPicker: Bool) {
        mutationLedger.cancel(windowID: windowID)
        runtimeState.invalidate(windowID: windowID)
        if dismissPicker {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            pickerController.dismiss(notify: false)
        }
    }

    private func invalidateAll(reason: String) {
        logger.notice("Invalidating volatile state: \(reason, privacy: .public)")
        diagnostics.record(category: "lifecycle", "invalidated: \(reason)")
        pendingDetections.values.forEach { $0.cancel() }
        pendingDetections.removeAll()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        placementTask?.cancel()
        placementTask = nil
        activeMutationWindowIDs.removeAll()
        thumbnailCache.removeAll()
        mutationLedger.cancelAll()
        runtimeState.invalidateAll()
        pickerController.dismiss(notify: false)
        linkedResizeController.cancelActiveDrag()
    }
}
