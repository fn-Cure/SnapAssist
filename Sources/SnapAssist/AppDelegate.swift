import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowSystem = WindowSystem()
    private var statusItem: NSStatusItem?
    private var isEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusMenu()
        windowSystem.start()
        _ = windowSystem.requestAccessibilityPermission(prompt: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowSystem.stop()
    }

    private func buildStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "SnapAssist")
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let toggle = NSMenuItem(
            title: isEnabled ? "SnapAssist pausieren" : "SnapAssist aktivieren",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let accessibility = NSMenuItem(
            title: windowSystem.isAccessibilityTrusted ? "Bedienungshilfen: erlaubt" : "Bedienungshilfen erlauben…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibility.target = self
        accessibility.isEnabled = !windowSystem.isAccessibilityTrusted
        menu.addItem(accessibility)

        let recording = NSMenuItem(
            title: windowSystem.hasScreenRecordingPermission ? "Bildschirmaufnahme: erlaubt" : "Bildschirmaufnahme erlauben…",
            action: #selector(requestScreenRecording),
            keyEquivalent: ""
        )
        recording.target = self
        recording.isEnabled = !windowSystem.hasScreenRecordingPermission
        menu.addItem(recording)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "SnapAssist beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        windowSystem.isEnabled = isEnabled
        statusItem?.menu = makeMenu()
    }

    @objc private func openAccessibilitySettings() {
        windowSystem.openAccessibilitySettings()
    }

    @objc private func requestScreenRecording() {
        windowSystem.requestScreenRecordingPermission()
        statusItem?.menu = makeMenu()
    }
}

