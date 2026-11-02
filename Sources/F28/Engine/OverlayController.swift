import AppKit
import F28Core

/// The engine: watches windows, resolves focus and keeps one overlay per display in place.
@MainActor
final class OverlayController {
    private let prefs: Preferences
    private let source = WindowSource()
    private let bars = BarsController()
    private var overlays: [CGDirectDisplayID: ScreenOverlay] = [:]
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var appearanceObservation: NSKeyValueObservation?
    private var lastAllWindowsActivation: (pid: pid_t, time: TimeInterval)?
    private var raiseWaitTicks = 0

    private(set) var isRunning = false
    private(set) var isPeeking = false
    private(set) var state = FocusState.empty

    /// Called when the engine starts, stops or the focused window changes.
    var onChange: (() -> Void)?

    private let logging = ProcessInfo.processInfo.environment["F28_LOG"] != nil

    init(prefs: Preferences) {
        self.prefs = prefs

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            self?.applicationActivated(note)
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.refresh() }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.source.forget(pid: app.processIdentifier)
            }
            self?.refresh()
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.rebuildScreens()
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyStyle() } }
        }
        rebuildScreens()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { handler(note) }
        }
        observers.append((center, token))
    }

    // MARK: - Lifecycle

    /// Re-read every preference: style, run state, Dock/menu bar hiding.
    func preferencesChanged() {
        applyStyle()
        if prefs.enabled != isRunning {
            setRunning(prefs.enabled)
        } else if isRunning {
            refresh()
        }
        bars.setHidden(prefs.enabled && prefs.autoHideBars)
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        overlays.values.forEach { $0.tearDown() }
        bars.restoreNow()
    }

    private func setRunning(_ on: Bool) {
        isRunning = on
        if on {
            let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            refresh()
        } else {
            timer?.invalidate()
            timer = nil
            isPeeking = false
            overlays.values.forEach { $0.hide(duration: fadeDuration) }
            state = .empty
        }
        onChange?()
    }

    private var fadeDuration: TimeInterval {
        prefs.revealEffect == .none ? 0.12 : max(0.2, prefs.transitionDuration)
    }

    // MARK: - Peek

    /// Temporarily reveal everything while Shift is held.
    func peek() {
        guard isRunning, !isPeeking else { return }
        setPeeking(true)
    }

    private func setPeeking(_ on: Bool) {
        isPeeking = on
        overlays.values.forEach { $0.setPeeking(on, duration: 0.18) }
    }

    // MARK: - Displays

    private func rebuildScreens() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = ScreenGeometry.displayID(of: screen) else { continue }
            seen.insert(id)
            let frame = CGDisplayBounds(id)
            if let overlay = overlays[id] {
                overlay.updateFrame(frame)
            } else {
                overlays[id] = ScreenOverlay(displayID: id, frame: frame, style: currentStyle(), mode: prefs.mode)
            }
        }
        for (id, overlay) in overlays where !seen.contains(id) {
            overlay.tearDown()
            overlays[id] = nil
        }
        refresh()
    }

    // MARK: - Style

    func currentStyle() -> BlurStyle {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tint: NSColor?
        switch prefs.tint {
        case .system: tint = dark ? NSColor.black.withAlphaComponent(0.22) : NSColor.white.withAlphaComponent(0.28)
        case .light: tint = NSColor.white.withAlphaComponent(0.32)
        case .dark: tint = NSColor.black.withAlphaComponent(0.3)
        case .custom: tint = prefs.customTint.withAlphaComponent(0.24)
        case .none: tint = nil
        }
        let base = 2 + CGFloat(prefs.blur) * 58
        return BlurStyle(radius: prefs.mode == .ambient ? base * 0.85 : base,
                         saturation: prefs.monochrome ? 0 : 1.05,
                         tint: tint,
                         dim: CGFloat(prefs.dim) * 0.6,
                         grain: CGFloat(prefs.grain) * 0.35)
    }

    func applyStyle() {
        let style = currentStyle()
        overlays.values.forEach { $0.apply(style: style, mode: prefs.mode) }
    }

    // MARK: - Focus tracking

    private func applicationActivated(_ note: Notification) {
        // App-wide focus: bring every window of the newly active app forward, the same as
        // clicking its Dock icon, so they form one contiguous run above the overlay.
        if isRunning, prefs.appWide,
           let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app != .current {
            let now = ProcessInfo.processInfo.systemUptime
            let recent = lastAllWindowsActivation.map { $0.pid == app.processIdentifier && now - $0.time < 1 } ?? false
            if !recent {
                lastAllWindowsActivation = (app.processIdentifier, now)
                app.activate(options: [.activateAllWindows])
            }
        }
        refresh()
    }

    var ownWindowIDs: Set<UInt32> { Set(overlays.values.flatMap(\.windowIDs)) }

    func refresh() {
        guard isRunning else { return }
        if isPeeking && !NSEvent.modifierFlags.contains(.shift) { setPeeking(false) }

        let windows = source.snapshot()
        let ours = ownWindowIDs
        let foreign = windows.filter { !ours.contains($0.id) }
        let candidates = foreign.filter { !WindowSource.systemOwners.contains($0.ownerName ?? "") }
        let front = NSWorkspace.shared.frontmostApplication
        let screens = overlays.map { ScreenInfo(id: $0.key, frame: $0.value.frame) }

        let resolved = FocusResolver.resolve(windows: candidates, frontPID: front?.processIdentifier,
                                             frontBundleID: front?.bundleIdentifier, screens: screens,
                                             options: prefs.focusOptions)
        // Mid app-switch the new app is frontmost before its window is raised. Hold the
        // current layout for a few ticks rather than briefly dropping the overlay deep into
        // the stack; if the window stays below another (rare), accept it after ~200 ms.
        if !resolved.focusIsOnTop && raiseWaitTicks < 4 {
            raiseWaitTicks += 1
            return
        }
        raiseWaitTicks = 0
        let context = ScreenOverlay.Context(
            windows: windows,
            byID: Dictionary(foreign.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            ours: ours,
            reveal: prefs.revealEffect,
            duration: prefs.transitionDuration,
            fadeDuration: fadeDuration
        )
        let stage = prefs.blurStageManager ? foreign.filter { $0.ownerName == "WindowManager" && $0.layer > 0 } : []

        for (id, overlay) in overlays {
            overlay.update(resolved.screens[id] ?? .hidden, context: context)
            overlay.updateStageManager(stage)
        }

        if resolved != state {
            let focusChanged = resolved.focusedWindowID != state.focusedWindowID
            state = resolved
            if logging { log(resolved, front: front) }
            if focusChanged { onChange?() }
        }
    }

    private func log(_ state: FocusState, front: NSRunningApplication?) {
        let screens = state.screens.sorted { $0.key < $1.key }.map { id, focus in
            "\(id)=\(focus.target.map { "below \($0.targetID) sharp \($0.sharpIDs)" } ?? "hidden")"
        }
        print("f/2.8 focus: app=\(front?.localizedName ?? "-") window=\(state.focusedWindowID.map(String.init) ?? "-") \(screens.joined(separator: " "))")
    }

    // MARK: - Diagnostics

    var engineDescription: String {
        let values = overlays.values
        if values.contains(where: \.usesFallbackBlur) { return "window-server blur (fallback)" }
        if let name = values.compactMap(\.backdropClassName).first { return "tuned backdrop (\(name))" }
        return "pending"
    }
}
