import AppKit

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var sequence = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        createWindow(title: "SnapAssist Fixture")
        createWindow(title: "SnapAssist Fixture")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item("Neues gleichnamiges Fenster", action: #selector(createSameTitleWindow), key: "n"))
        appMenu.addItem(item("Titel des Frontfensters ändern", action: #selector(changeFrontTitle), key: "t"))
        appMenu.addItem(item("Frontfenster links anordnen", action: #selector(snapFrontLeft), key: "l"))
        appMenu.addItem(item("Modales Fenster öffnen", action: #selector(openModal), key: "m"))
        appMenu.addItem(item("UI 750 ms blockieren", action: #selector(blockMainThread), key: "b"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Fixture beenden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func createSameTitleWindow() {
        createWindow(title: "SnapAssist Fixture")
    }

    @objc private func changeFrontTitle() {
        sequence += 1
        NSApplication.shared.keyWindow?.title = "Fixture Title \(sequence)"
    }

    @objc private func openModal() {
        let alert = NSAlert()
        alert.messageText = "Modal Test Window"
        alert.informativeText = "Dieses Fenster muss vom SnapAssist-Picker ausgeschlossen bleiben."
        alert.addButton(withTitle: "Schließen")
        alert.runModal()
    }

    @objc private func snapFrontLeft() {
        guard let window = NSApplication.shared.keyWindow,
              let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        window.setFrame(
            NSRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height),
            display: true,
            animate: false
        )
    }

    @objc private func blockMainThread() {
        Thread.sleep(forTimeInterval: 0.75)
    }

    private func createWindow(title: String) {
        let offset = CGFloat(windows.count * 34)
        let window = NSWindow(
            contentRect: NSRect(x: 180 + offset, y: 180 + offset, width: 640, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 24, weight: .bold)
        let explanation = NSTextField(wrappingLabelWithString: "Testfenster für stabile IDs, Mindestgrößen, AX-Read-back und gleichnamige Fenster.")
        explanation.textColor = .secondaryLabelColor
        let titleButton = NSButton(title: "Titel ändern", target: self, action: #selector(changeFrontTitle))
        let snapButton = NSButton(title: "Links anordnen", target: self, action: #selector(snapFrontLeft))
        let modalButton = NSButton(title: "Modal öffnen", target: self, action: #selector(openModal))
        let blockButton = NSButton(title: "750 ms blockieren", target: self, action: #selector(blockMainThread))

        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(explanation)
        stack.addArrangedSubview(titleButton)
        stack.addArrangedSubview(snapButton)
        stack.addArrangedSubview(modalButton)
        stack.addArrangedSubview(blockButton)
        window.contentView = stack
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = FixtureDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
}
