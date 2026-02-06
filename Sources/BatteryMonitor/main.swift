import AppKit

let app = NSApplication.shared
let delegate = { @MainActor in AppDelegate() }()
app.delegate = delegate
app.run()
