import AppKit
import OSLog
import SnapAssistCore
import SwiftUI

@MainActor
final class PickerZoneModel: ObservableObject {
    let zoneID: Int
    let targetLabel: String
    let candidates: [WindowDescriptor]
    @Published var thumbnails: [String: NSImage]
    let icons: [String: NSImage]
    @Published var active: Bool
    @Published var selectedCandidateID: String?
    @Published var errorMessage: String?

    init(
        zoneID: Int,
        targetLabel: String,
        candidates: [WindowDescriptor],
        thumbnails: [String: NSImage],
        icons: [String: NSImage],
        active: Bool,
        selectedCandidateID: String?
    ) {
        self.zoneID = zoneID
        self.targetLabel = targetLabel
        self.candidates = candidates
        self.thumbnails = thumbnails
        self.icons = icons
        self.active = active
        self.selectedCandidateID = selectedCandidateID
        self.errorMessage = nil
    }
}

struct PickerZoneView: View {
    @ObservedObject var model: PickerZoneModel
    let onSelect: (String, Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 118, maximum: 190), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.on.rectangle.angled")
                Text(model.targetLabel)
                    .font(.headline)
                Spacer()
                Text("Esc")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Fehler: \(errorMessage)")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(model.candidates) { candidate in
                            Button {
                                onSelect(candidate.id, model.zoneID)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    preview(for: candidate)
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(16 / 10, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    HStack(spacing: 6) {
                                        if let icon = model.icons[candidate.id] {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 18, height: 18)
                                        }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(candidate.title.isEmpty ? candidate.appName : candidate.title)
                                                .lineLimit(1)
                                                .font(.caption.weight(.medium))
                                            Text(candidate.appName)
                                                .lineLimit(1)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(7)
                                .background(cardBackground(for: candidate))
                            }
                            .id(candidate.id)
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                candidate.title.isEmpty
                                    ? candidate.appName
                                    : "\(candidate.appName), \(candidate.title)"
                            )
                            .accessibilityHint("In \(model.targetLabel) platzieren")
                            .accessibilityAddTraits(
                                model.active && model.selectedCandidateID == candidate.id ? .isSelected : []
                            )
                        }
                    }
                }
                .onChange(of: model.selectedCandidateID) { _, candidateID in
                    guard model.active, let candidateID else { return }
                    proxy.scrollTo(candidateID, anchor: .center)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(model.active ? Color.accentColor : Color.white.opacity(0.25), lineWidth: model.active ? 3 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .padding(8)
    }

    @ViewBuilder
    private func preview(for candidate: WindowDescriptor) -> some View {
        if let thumbnail = model.thumbnails[candidate.id] {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let icon = model.icons[candidate.id] {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func cardBackground(for candidate: WindowDescriptor) -> some ShapeStyle {
        model.active && model.selectedCandidateID == candidate.id
            ? AnyShapeStyle(Color.accentColor.opacity(0.22))
            : AnyShapeStyle(Color.primary.opacity(0.07))
    }
}

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PickerController {
    var onSelect: ((String, Int) -> Void)?
    var onCancel: (() -> Void)?

    private var panels: [Int: PickerPanel] = [:]
    private var models: [Int: PickerZoneModel] = [:]
    private var navigation = PickerNavigation(zoneIDs: [], candidateIDs: [])
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private let logger = Logger(subsystem: "com.caner.snapassist", category: "Picker")
    private let diagnostics = DiagnosticsStore.shared

    var isVisible: Bool { !panels.isEmpty }

    func present(session: AssistSession, thumbnails: [String: NSImage]) {
        dismiss(notify: false, reason: "replace presentation")
        guard !session.emptyZoneIDs.isEmpty, !session.candidates.isEmpty else { return }

        navigation = PickerNavigation(
            zoneIDs: session.emptyZoneIDs,
            candidateIDs: session.candidates.map(\.id)
        )
        let icons = Dictionary(uniqueKeysWithValues: session.candidates.compactMap { candidate in
            NSRunningApplication(processIdentifier: candidate.processID)?.icon.map { (candidate.id, $0) }
        })

        for zoneID in session.emptyZoneIDs {
            let model = PickerZoneModel(
                zoneID: zoneID,
                targetLabel: zoneLabel(for: zoneID, layout: session.group.layout),
                candidates: session.candidates,
                thumbnails: thumbnails,
                icons: icons,
                active: navigation.activeZoneID == zoneID,
                selectedCandidateID: navigation.selectedCandidateID
            )
            let panel = PickerPanel(
                contentRect: session.group.layout.zoneFrames[zoneID],
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: PickerZoneView(model: model) { [weak self] windowID, selectedZoneID in
                self?.onSelect?(windowID, selectedZoneID)
            })
            panel.setFrame(session.group.layout.zoneFrames[zoneID], display: true)
            panel.orderFrontRegardless()
            panels[zoneID] = panel
            models[zoneID] = model
        }

        installEventMonitors()
        if let activeZone = navigation.activeZoneID {
            panels[activeZone]?.makeKey()
        }
        logger.notice(
            "Presented \(self.panels.count) picker panel(s) for zones=\(session.emptyZoneIDs, privacy: .public) candidates=\(session.candidates.count) frames=\(session.emptyZoneIDs.map { String(describing: session.group.layout.zoneFrames[$0]) }, privacy: .public)"
        )
        diagnostics.record(
            category: "picker",
            "presented panels=\(panels.count), candidates=\(session.candidates.count)"
        )
    }

    func updateThumbnails(_ thumbnails: [String: NSImage]) {
        guard !thumbnails.isEmpty else { return }
        for model in models.values {
            model.thumbnails.merge(thumbnails) { _, new in new }
        }
    }

    func showError(_ message: String) {
        for model in models.values {
            model.errorMessage = message
        }
        NSSound.beep()
    }

    func dismiss(notify: Bool = true, reason: String = "requested") {
        if !panels.isEmpty {
            logger.notice("Dismissed \(self.panels.count) picker panel(s): \(reason, privacy: .public)")
            diagnostics.record(category: "picker", "dismissed panels=\(panels.count), reason=\(reason)")
        }
        removeEventMonitors()
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        models.removeAll()
        navigation = PickerNavigation(zoneIDs: [], candidateIDs: [])
        if notify { onCancel?() }
    }

    private func installEventMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        let outsideMouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: outsideMouseEvents) { [weak self] event in
            self?.cancelIfOutsidePanels(point: NSEvent.mouseLocation)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: outsideMouseEvents) { [weak self] _ in
            self?.cancelIfOutsidePanels(point: NSEvent.mouseLocation)
        }
    }

    private func removeEventMonitors() {
        [localKeyMonitor, localMouseMonitor, globalMouseMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        localKeyMonitor = nil
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            dismiss(reason: "Escape")
        case 48:
            navigation.moveZone(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            updateSelection()
        case 123, 126:
            navigation.moveCandidate(by: -1)
            updateSelection()
        case 124, 125:
            navigation.moveCandidate(by: 1)
            updateSelection()
        case 36, 76:
            if let windowID = navigation.selectedCandidateID,
               let zoneID = navigation.activeZoneID {
                onSelect?(windowID, zoneID)
            }
        default:
            return false
        }
        return true
    }

    private func updateSelection() {
        for (zoneID, model) in models {
            model.active = zoneID == navigation.activeZoneID
            model.selectedCandidateID = navigation.selectedCandidateID
        }
        if let activeZone = navigation.activeZoneID {
            panels[activeZone]?.makeKey()
        }
    }

    private func cancelIfOutsidePanels(point: CGPoint) {
        guard panels.values.allSatisfy({ !$0.frame.contains(point) }) else { return }
        dismiss(reason: "outside click at \(point)")
    }


    private func zoneLabel(for zoneID: Int, layout: LayoutGeometry) -> String {
        switch layout.kind {
        case .halves:
            return zoneID == 0 ? "Linke Hälfte" : "Rechte Hälfte"
        case .thirds:
            return ["Linkes Drittel", "Mittleres Drittel", "Rechtes Drittel"][zoneID]
        case .quarters:
            return ["Oben links", "Oben rechts", "Unten links", "Unten rechts"][zoneID]
        }
    }
}
