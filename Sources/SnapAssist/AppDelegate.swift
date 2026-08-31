import AppKit
import SnapAssistCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let accessibilityPromptKey = "hasRequestedAccessibilityPermission"
    private let coordinator = AppCoordinator()
    private lazy var preferencesModel = AppPreferencesModel(coordinator: coordinator)
    private var statusItem: NSStatusItem?
    private var settingsWindowController: AppWindowController?
    private var onboardingWindowController: AppWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
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
        preferencesModel.refresh()
        if !preferencesModel.onboardingCompleted {
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
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

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Einstellungen…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "SnapAssist beenden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(
            title: preferencesModel.isEnabled ? "SnapAssist pausieren" : "SnapAssist aktivieren",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let accessibility = NSMenuItem(
            title: preferencesModel.accessibilityTrusted ? "Bedienungshilfen: erlaubt" : "Bedienungshilfen erlauben…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibility.target = self
        accessibility.isEnabled = !preferencesModel.accessibilityTrusted
        menu.addItem(accessibility)

        let recording = NSMenuItem(
            title: preferencesModel.screenRecordingGranted ? "Bildschirmaufnahme: erlaubt" : "Bildschirmaufnahme erlauben…",
            action: #selector(requestScreenRecording),
            keyEquivalent: ""
        )
        recording.target = self
        recording.isEnabled = !preferencesModel.screenRecordingGranted
        menu.addItem(recording)

        let linkedResize = NSMenuItem(
            title: preferencesModel.linkedResizingEnabled && !coordinator.linkedResizeMonitorInstalled
                ? "Gekoppeltes Resize: Monitorfehler"
                : "Gekoppeltes Resize (experimentell)",
            action: #selector(toggleLinkedResizing),
            keyEquivalent: ""
        )
        linkedResize.target = self
        linkedResize.state = preferencesModel.linkedResizingEnabled ? .on : .off
        menu.addItem(linkedResize)

        let observerHealth = NSMenuItem(
            title: observerStatusTitle,
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(observerHealth)

        if let failure = coordinator.windowSystem.lastMutationFailureDescription {
            menu.addItem(NSMenuItem(title: "Letzter Fehler: \(failure)", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Einstellungen…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let onboarding = NSMenuItem(title: "Einführung anzeigen…", action: #selector(showOnboarding), keyEquivalent: "")
        onboarding.target = self
        menu.addItem(onboarding)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "SnapAssist beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        preferencesModel.setEnabled(!preferencesModel.isEnabled)
        rebuildMenu()
    }

    @objc private func openAccessibilitySettings() {
        preferencesModel.openAccessibilitySettings()
    }

    @objc private func requestScreenRecording() {
        preferencesModel.requestScreenRecording()
        rebuildMenu()
    }

    @objc private func toggleLinkedResizing() {
        preferencesModel.setLinkedResizingEnabled(!preferencesModel.linkedResizingEnabled)
        rebuildMenu()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = AppWindowController(kind: .settings, model: preferencesModel)
        }
        preferencesModel.refresh()
        settingsWindowController?.show()
    }

    @objc private func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = AppWindowController(
                kind: .onboarding,
                model: preferencesModel
            ) { [weak self] in
                self?.onboardingWindowController?.close()
            }
        }
        preferencesModel.refresh()
        onboardingWindowController?.show()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        preferencesModel.refresh()
        populate(menu)
    }

    private func rebuildMenu() {
        let menu = makeMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private var observerStatusTitle: String {
        let degraded = coordinator.windowSystem.degradedObserverCount
        let failures = coordinator.windowSystem.observerFailureCount
        if degraded == 0 && failures == 0 { return "Fensterbeobachtung: bereit" }
        if degraded > 0 && failures == 0 {
            return "Fensterbeobachtung: \(degraded) App(s) im Fallback"
        }
        return "Fensterbeobachtung: \(failures) Fehler, \(degraded) Fallback"
    }
}
