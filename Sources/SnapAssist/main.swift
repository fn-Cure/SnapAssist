import AppKit

private let delegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()

