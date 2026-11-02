import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppCommands {
    private let prefs = Preferences.shared
    private var engine: OverlayController!
    private var status: StatusMenuController!
    private var controls: ControlDotController!
    private var settings: SettingsWindowController!
    private let gestures = GestureMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var changeScheduled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundle = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundle).contains(where: { $0 != .current }) {
            NSLog("f/2.8 is already running")
            NSApp.terminate(nil)
            return
        }

        engine = OverlayController(prefs: prefs)
        status = StatusMenuController(prefs: prefs, commands: self)
        settings = SettingsWindowController(prefs: prefs) { [weak self] in self?.engine.engineDescription ?? "" }
        controls = ControlDotController(prefs: prefs,
                                        onToggle: { [weak self] in self?.toggleFocus() },
                                        menu: { [weak self] in self?.status.contextMenu() ?? NSMenu() })
        engine.onChange = { [weak self] in self?.reflectState() }

        let hotKeys = HotKeyCenter.shared
        hotKeys.register(Shortcuts.toggle) { [weak self] in self?.toggleFocus() }
        hotKeys.register(Shortcuts.switchMode) { [weak self] in self?.switchMode() }
        hotKeys.register(Shortcuts.ignoreApp) { [weak self] in self?.ignoreFrontmostApp() }
        hotKeys.register(Shortcuts.toggleControls) { [weak self] in self?.toggleControls() }

        gestures.onShake = { [weak self] flags in self?.handleShake(flags) }
        gestures.start()

        // Coalesce bursts of changes (slider drags) into one update per run-loop turn.
        prefs.objectWillChange
            .sink { [weak self] _ in self?.scheduleChange() }
            .store(in: &cancellables)

        preferencesChanged()

        if !prefs.hasLaunchedBefore {
            prefs.hasLaunchedBefore = true
            showSettings()
            Toast.shared.show("f/2.8 is on — shake the cursor or press ⌃⌥⌘F to toggle", symbol: "camera.aperture")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.shutdown()
    }

    private func scheduleChange() {
        guard !changeScheduled else { return }
        changeScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.changeScheduled = false
                self?.preferencesChanged()
            }
        }
    }

    private func preferencesChanged() {
        engine.preferencesChanged()
        gestures.sensitivity = prefs.shakeSensitivity
        applyDockPresence()
        reflectState()
    }

    private func applyDockPresence() {
        let policy: NSApplication.ActivationPolicy = prefs.showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { NSApp.mainMenu = MainMenu.make(commands: self) }
    }

    private func reflectState() {
        status.refreshIcon()
        controls.refresh()
    }

    private func handleShake(_ flags: NSEvent.ModifierFlags) {
        if flags.contains(.shift) {
            guard prefs.shakeToPeek, prefs.enabled else { return }
            engine.peek()
            Toast.shared.show("Peeking — release ⇧ to refocus", symbol: "eye")
        } else if prefs.shakeToToggle {
            toggleFocus()
        }
    }

    // MARK: - AppCommands

    func toggleFocus() {
        prefs.enabled.toggle()
        Toast.shared.show(prefs.enabled ? "Focus on" : "Focus off",
                          symbol: prefs.enabled ? "camera.aperture" : "circle.dashed")
    }

    func switchMode() { setMode(prefs.mode.next) }

    func setMode(_ mode: FocusMode) {
        prefs.mode = mode
        if !prefs.enabled { prefs.enabled = true }
        Toast.shared.show(mode.title, symbol: mode == .deep ? "circle.fill" : "circle.lefthalf.filled")
    }

    func ignoreFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication, app != .current,
              let bundle = app.bundleIdentifier else { return }
        prefs.toggleIgnored(bundle)
        let name = app.localizedName ?? bundle
        Toast.shared.show(prefs.isIgnored(bundle) ? "Ignoring \(name)" : "Focusing \(name) again",
                          symbol: prefs.isIgnored(bundle) ? "eye.slash" : "eye")
    }

    func toggleControls() { prefs.showControls.toggle() }

    func showSettings() { settings.show() }
}
