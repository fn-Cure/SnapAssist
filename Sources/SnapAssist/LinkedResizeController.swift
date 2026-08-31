import AppKit
import SnapAssistCore

@MainActor
final class LinkedResizeController {
    typealias GroupsProvider = () -> [String: LayoutGroup]
    typealias MutationRegistrationHandler = (UUID, String, CGRect) -> Void
    typealias VerifiedFramesHandler = (String, [String: CGRect]) -> Void

    private struct ActiveDrag {
        let screenID: String
        let divider: SharedDivider
        let members: [LayoutMember]
        let driverWindowID: String
    }

    private let windowSystem: WindowSystem
    private let groupsProvider: GroupsProvider
    private let mutationRegistered: MutationRegistrationHandler
    private let shouldIgnore: () -> Bool
    private let onVerifiedFrames: VerifiedFramesHandler
    private let onFailure: () -> Void
    private var eventMonitor: Any?
    private var activeDrag: ActiveDrag?

    var isEnabled = false {
        didSet {
            isEnabled ? start() : stop()
        }
    }

    var monitorInstalled: Bool { eventMonitor != nil }

    init(
        windowSystem: WindowSystem,
        groupsProvider: @escaping GroupsProvider,
        mutationRegistered: @escaping MutationRegistrationHandler,
        shouldIgnore: @escaping () -> Bool,
        onVerifiedFrames: @escaping VerifiedFramesHandler,
        onFailure: @escaping () -> Void
    ) {
        self.windowSystem = windowSystem
        self.groupsProvider = groupsProvider
        self.mutationRegistered = mutationRegistered
        self.shouldIgnore = shouldIgnore
        self.onVerifiedFrames = onVerifiedFrames
        self.onFailure = onFailure
    }

    func start() {
        guard isEnabled, eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        activeDrag = nil
    }

    func cancelActiveDrag() {
        activeDrag = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            begin(at: NSEvent.mouseLocation)
        case .leftMouseUp:
            finish()
        default:
            break
        }
    }

    private func begin(at point: CGPoint) {
        guard isEnabled, !shouldIgnore(), windowSystem.isEnabled, windowSystem.isAccessibilityTrusted else {
            activeDrag = nil
            return
        }

        let groups = groupsProvider()
        guard !groups.isEmpty else {
            activeDrag = nil
            return
        }

        let windows = windowSystem.visibleWindows()
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })

        for group in groups.values where group.isComplete && LayoutGroupValidator.isValid(group, windows: windows) {
            guard group.members.keys.allSatisfy({ windowsByID[$0] != nil }),
                  let focusedID = windowSystem.focusedWindowID(),
                  group.members[focusedID] != nil else {
                continue
            }
            let members = group.members.keys.compactMap { id -> LayoutMember? in
                guard let window = windowsByID[id] else { return nil }
                return LayoutMember(id: id, frame: window.frame)
            }
            guard members.count == group.members.count,
                  let divider = DividerSolver.findDivider(at: point, members: members) else {
                continue
            }

            activeDrag = ActiveDrag(
                screenID: group.screenID,
                divider: divider,
                members: members,
                driverWindowID: focusedID
            )
            return
        }

        activeDrag = nil
    }

    private func finish() {
        guard let drag = activeDrag else { return }
        activeDrag = nil

        let windows = windowSystem.visibleWindows()
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        guard let driver = windowsByID[drag.driverWindowID],
              drag.members.allSatisfy({ windowsByID[$0.id]?.screenID == drag.screenID }) else {
            onFailure()
            return
        }

        let position: CGFloat
        switch drag.divider.orientation {
        case .vertical:
            position = drag.divider.leadingWindowIDs.contains(drag.driverWindowID)
                ? driver.frame.maxX + drag.divider.gap / 2
                : driver.frame.minX - drag.divider.gap / 2
        case .horizontal:
            position = drag.divider.leadingWindowIDs.contains(drag.driverWindowID)
                ? driver.frame.maxY + drag.divider.gap / 2
                : driver.frame.minY - drag.divider.gap / 2
        }

        guard let frames = DividerSolver.resize(
            divider: drag.divider,
            to: position,
            members: drag.members
        ) else {
            onFailure()
            return
        }

        let operationID = UUID()
        var verifiedFrames = frames
        verifiedFrames[drag.driverWindowID] = driver.frame
        for (windowID, targetFrame) in frames where windowID != drag.driverWindowID {
            mutationRegistered(operationID, windowID, targetFrame)
            let result = windowSystem.setFrame(targetFrame, for: windowID)
            guard result.succeeded, let frameAfter = result.frameAfter else {
                onFailure()
                return
            }
            verifiedFrames[windowID] = frameAfter
        }
        onVerifiedFrames(drag.screenID, verifiedFrames)
    }
}
