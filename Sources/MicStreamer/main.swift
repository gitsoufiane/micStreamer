import AppKit

if #available(macOS 14.2, *) {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
} else {
    fputs("MicStreamer needs macOS 14.2 or newer.\n", stderr)
    exit(1)
}
