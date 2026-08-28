import AppKit
import OSLog
import SnapAssistCore

final class AppCoordinator {
    let windowSystem: WindowSystem

    private let thumbnailProvider: ThumbnailProvider
    private let pickerController: PickerController
    private var eventGate = WindowEventGate(cooldown: 1.0)
    private var activeSession: AssistSession?
    private(set) var groups: [String: LayoutGroup] = [:]
    private var debounceWorkItem: DispatchWorkItem?
    private var presentationGeneration = UUID()
    private let logger = Logger(subsystem: "com.caner.snapassist", category: "Coordinator")
    private lazy var linkedResizeController = LinkedResizeController(
        windowSystem: windowSystem,
        groupsProvider: { [weak self] in self?.groups ?? [:] },
        suppress: { [weak self] windowIDs in self?.suppressProgrammaticChanges(windowIDs) },
        shouldIgnore: { [weak self] in self?.pickerController.isVisible ?? true }
    )

    var isEnabled: Bool {
        get { windowSystem.isEnabled }
        set {
            windowSystem.isEnabled = newValue
            if !newValue {
                pickerController.dismiss(notify: false)
                activeSession = nil
            }
        }
    }

    init(
        windowSystem: WindowSystem = WindowSystem(),
        thumbnailProvider: ThumbnailProvider = ThumbnailProvider(),
        pickerController: PickerController = PickerController()
    ) {
        self.windowSystem = windowSystem
        self.thumbnailProvider = thumbnailProvider
        self.pickerController = pickerController
        pickerController.onSelect = { [weak self] windowID, zoneID in
            self?.place(windowID: windowID, into: zoneID)
        }
        pickerController.onCancel = { [weak self] in
            self?.activeSession = nil
        }
    }

    func start() {
        windowSystem.onEvent = { [weak self] event in
            self?.handle(event)
        }
        windowSystem.start()
        linkedResizeController.start()
    }

    func stop() {
        debounceWorkItem?.cancel()
        pickerController.dismiss(notify: false)
        linkedResizeController.stop()
        windowSystem.stop()
    }

    private func handle(_ event: WindowSystemEvent) {
        guard isEnabled else { return }
        switch event {
        case let .geometryChanged(windowID):
            scheduleSnapDetection(windowID: windowID)
        case .inventoryChanged:
            validateGroups()
        case .focusChanged:
            break
        }
    }

    private func scheduleSnapDetection(windowID: String) {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.detectSnap(windowID: windowID)
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    private func detectSnap(windowID: String) {
        let windows = windowSystem.visibleWindows()
        guard let trigger = windows.first(where: { $0.id == windowID }),
              let screenFrame = windowSystem.screenFrame(for: trigger.screenID),
              eventGate.shouldHandle(
                windowID: trigger.id,
                frame: trigger.frame,
                at: ProcessInfo.processInfo.systemUptime
              ),
              let session = LayoutStateBuilder.buildSession(
                trigger: trigger,
                windowsOnTargetScreen: windows.filter { $0.screenID == trigger.screenID },
                allVisibleWindows: windows,
                screenFrame: screenFrame,
                ownProcessID: ProcessInfo.processInfo.processIdentifier
              ) else {
            logger.debug("Geometry event did not produce a supported snap for \(windowID, privacy: .public)")
            return
        }

        logger.notice("Detected \(session.group.layout.kind.rawValue, privacy: .public) snap with \(session.emptyZoneIDs.count) empty zones and \(session.candidates.count) candidates")
        groups[trigger.screenID] = session.group
        activeSession = session

        guard !session.emptyZoneIDs.isEmpty, !session.candidates.isEmpty else {
            pickerController.dismiss(notify: false)
            return
        }

        let generation = UUID()
        presentationGeneration = generation
        Task { [weak self] in
            guard let self else { return }
            let thumbnails = await thumbnailProvider.thumbnails(for: session.candidates)
            await MainActor.run {
                guard self.presentationGeneration == generation,
                      self.activeSession?.group == session.group else { return }
                self.pickerController.present(session: session, thumbnails: thumbnails)
            }
        }
    }

    private func place(windowID: String, into zoneID: Int) {
        guard var session = activeSession,
              let targetFrame = session.place(windowID: windowID, into: zoneID) else {
            return
        }

        eventGate.suppress(
            windowID: windowID,
            until: ProcessInfo.processInfo.systemUptime + 0.8
        )
        guard windowSystem.setFrame(targetFrame, for: windowID) else {
            NSSound.beep()
            return
        }

        _ = windowSystem.raise(windowID: windowID)
        activeSession = session
        groups[session.group.screenID] = session.group

        if session.emptyZoneIDs.isEmpty || session.candidates.isEmpty {
            pickerController.dismiss(notify: false)
            activeSession = nil
        } else {
            let updatedSession = session
            Task { [weak self] in
                guard let self else { return }
                let thumbnails = await thumbnailProvider.thumbnails(for: updatedSession.candidates)
                await MainActor.run {
                    guard self.activeSession == updatedSession else { return }
                    self.pickerController.present(session: updatedSession, thumbnails: thumbnails)
                }
            }
        }
    }

    private func validateGroups() {
        let windows = windowSystem.visibleWindows()
        let ids = Set(windows.map(\.id))
        groups = groups.filter { _, group in
            Set(group.members.keys).isSubset(of: ids)
        }
        if let session = activeSession,
           !Set(session.group.members.keys).isSubset(of: ids) {
            pickerController.dismiss(notify: false)
            activeSession = nil
        }
    }

    private func suppressProgrammaticChanges(_ windowIDs: [String]) {
        let deadline = ProcessInfo.processInfo.systemUptime + 1.0
        for windowID in windowIDs {
            eventGate.suppress(windowID: windowID, until: deadline)
        }
    }
}
