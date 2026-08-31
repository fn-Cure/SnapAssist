import AppKit
import SnapAssistCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let accessibilityPromptKey = "hasRequestedAccessibilityPermission"
    private let coordinator = AppCoordinator()
    private var statusItem: NSStatusItem?
    private var isEnabled = true
    private var linkedResizingEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusMenu()
        let defaults = UserDefaults.standard
        if AccessibilityPromptPolicy.shouldPrompt(
            isTrusted: coordinator.windowSystem.isAccessibilityTrusted,
            hasRequestedBefore: defaults.bool(forKey: accessibilityPromptKey)
        ) {
            defaults.set(true, forKey: accessibilityPromptKey)
            _ = coordinator.windowSystem.requestAccessibilityPermission(prompt: true)
        }
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        coordinator.windowSystem.refreshAccessibilityState()
    }

    private func buildStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "SnapAssist")
        item.menu = makeMenu()
        item.menu?.delegate = self
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(
            title: isEnabled ? "SnapAssist pausieren" : "SnapAssist aktivieren",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let accessibility = NSMenuItem(
            title: coordinator.windowSystem.isAccessibilityTrusted ? "Bedienungshilfen: erlaubt" : "Bedienungshilfen erlauben…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibility.target = self
        accessibility.isEnabled = !coordinator.windowSystem.isAccessibilityTrusted
        menu.addItem(accessibility)

        let recording = NSMenuItem(
            title: coordinator.windowSystem.hasScreenRecordingPermission ? "Bildschirmaufnahme: erlaubt" : "Bildschirmaufnahme erlauben…",
            action: #selector(requestScreenRecording),
            keyEquivalent: ""
        )
        recording.target = self
        recording.isEnabled = !coordinator.windowSystem.hasScreenRecordingPermission
        menu.addItem(recording)

        let linkedResize = NSMenuItem(
            title: linkedResizingEnabled && !coordinator.linkedResizeMonitorInstalled
                ? "Gekoppeltes Resize: Monitorfehler"
                : "Gekoppeltes Resize (experimentell)",
            action: #selector(toggleLinkedResizing),
            keyEquivalent: ""
        )
        linkedResize.target = self
        linkedResize.state = linkedResizingEnabled ? .on : .off
        menu.addItem(linkedResize)

        let observerHealth = NSMenuItem(
            title: coordinator.windowSystem.observerFailureCount == 0
                ? "AX-Observer: bereit"
                : "AX-Observer: \(coordinator.windowSystem.observerFailureCount) Fehler",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(observerHealth)

        if let failure = coordinator.windowSystem.lastMutationFailureDescription {
            menu.addItem(NSMenuItem(title: "Letzter Fehler: \(failure)", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "SnapAssist beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        coordinator.isEnabled = isEnabled
        rebuildMenu()
    }

    @objc private func openAccessibilitySettings() {
        coordinator.windowSystem.openAccessibilitySettings()
    }

    @objc private func requestScreenRecording() {
        coordinator.windowSystem.requestScreenRecordingPermission()
        rebuildMenu()
    }

    @objc private func toggleLinkedResizing() {
        linkedResizingEnabled.toggle()
        coordinator.linkedResizingEnabled = linkedResizingEnabled
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func rebuildMenu() {
        let menu = makeMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }
}
