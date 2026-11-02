import AppKit

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--diagnose") {
        Diagnostics.run()
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
