import AppKit

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.run()
}
