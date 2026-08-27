import AppKit
import SnapAssistCore

final class LinkedResizeController {
    typealias GroupsProvider = () -> [String: LayoutGroup]
    typealias SuppressionHandler = ([String]) -> Void

    private struct ActiveDrag {
        let divider: SharedDivider
        let members: [LayoutMember]
        let driverWindowID: String?
        var lastPosition: CGFloat
    }

    private let windowSystem: WindowSystem
    private let groupsProvider: GroupsProvider
    private let suppress: SuppressionHandler
    private let shouldIgnore: () -> Bool
    private var eventMonitor: Any?
    private var activeDrag: ActiveDrag?
    private var lastUpdateTimestamp: TimeInterval = 0

    init(
        windowSystem: WindowSystem,
        groupsProvider: @escaping GroupsProvider,
        suppress: @escaping SuppressionHandler,
        shouldIgnore: @escaping () -> Bool
    ) {
        self.windowSystem = windowSystem
        self.groupsProvider = groupsProvider
        self.suppress = suppress
        self.shouldIgnore = shouldIgnore
    }

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        activeDrag = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            begin(at: NSEvent.mouseLocation)
        case .leftMouseDragged:
            update(at: NSEvent.mouseLocation, timestamp: event.timestamp)
        case .leftMouseUp:
            finish(at: NSEvent.mouseLocation)
        default:
            break
        }
    }

    private func begin(at point: CGPoint) {
        guard !shouldIgnore(), windowSystem.isEnabled, windowSystem.isAccessibilityTrusted else {
            activeDrag = nil
            return
        }

        let windows = windowSystem.visibleWindows()
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })

        for group in groupsProvider().values {
            let members = group.members.keys.compactMap { id -> LayoutMember? in
                guard let window = windowsByID[id] else { return nil }
                return LayoutMember(id: id, frame: window.frame)
            }
            guard members.count >= 2,
                  let divider = DividerSolver.findDivider(at: point, members: members) else {
                continue
            }

            let focusedID = windowSystem.focusedWindowID()
            activeDrag = ActiveDrag(
                divider: divider,
                members: members,
                driverWindowID: focusedID.flatMap { id in members.contains(where: { $0.id == id }) ? id : nil },
                lastPosition: divider.position
            )
            lastUpdateTimestamp = 0
            return
        }

        activeDrag = nil
    }

    private func update(at point: CGPoint, timestamp: TimeInterval) {
        guard var drag = activeDrag, timestamp - lastUpdateTimestamp >= 1.0 / 60.0 else { return }
        lastUpdateTimestamp = timestamp
        let position = drag.divider.orientation == .vertical ? point.x : point.y
        drag.lastPosition = position
        activeDrag = drag
        apply(drag: drag, includeDriver: false)
    }

    private func finish(at point: CGPoint) {
        guard var drag = activeDrag else { return }
        drag.lastPosition = drag.divider.orientation == .vertical ? point.x : point.y
        activeDrag = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.apply(drag: drag, includeDriver: true)
        }
    }

    private func apply(drag: ActiveDrag, includeDriver: Bool) {
        let frames = DividerSolver.resize(
            divider: drag.divider,
            to: drag.lastPosition,
            members: drag.members
        )
        let targetIDs = frames.keys.filter { includeDriver || $0 != drag.driverWindowID }
        suppress(Array(targetIDs))

        for id in targetIDs {
            guard let frame = frames[id] else { continue }
            _ = windowSystem.setFrame(frame, for: id)
        }
    }
}

