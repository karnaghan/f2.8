import AppKit
import F28Core

/// `f2.8 --diagnose`: checks the private APIs and the blur engine on this Mac, prints the
/// current focus resolution, then exits. Nothing is changed.
@MainActor
enum Diagnostics {
    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        print("f/2.8 diagnostics — macOS \(os)")
        print("  CABackdropLayer:            \(PrivateAPI.hasBackdropLayer ? "available" : "missing")")
        print("  CAFilter:                   \(PrivateAPI.hasFilters ? "available" : "missing")")
        print("  CGS window blur (fallback): \(PrivateAPI.hasWindowBlur ? "available" : "missing")")
        for (name, type) in [("gaussianBlur", "gaussianBlur"), ("colorSaturate", "colorSaturate")] {
            print("  filter \(name):\(String(repeating: " ", count: 14 - name.count)) \(PrivateAPI.filter(type, name: name) == nil ? "missing" : "ok")")
        }

        let source = WindowSource()
        let windows = source.snapshot()
        let front = NSWorkspace.shared.frontmostApplication
        let screens = NSScreen.screens.compactMap { screen -> ScreenInfo? in
            guard let id = ScreenGeometry.displayID(of: screen) else { return nil }
            return ScreenInfo(id: id, frame: CGDisplayBounds(id))
        }
        let state = FocusResolver.resolve(
            windows: windows.filter { !WindowSource.systemOwners.contains($0.ownerName ?? "") },
            frontPID: front?.processIdentifier, frontBundleID: front?.bundleIdentifier,
            screens: screens, options: Preferences.shared.focusOptions)
        print("  displays:                   \(screens.count)")
        print("  on-screen windows:          \(windows.count) (\(windows.filter { $0.layer == 0 }.count) normal)")
        print("  frontmost app:              \(front?.localizedName ?? "none")")
        print("  focused window:             \(state.focusedWindowID.map(String.init) ?? "none")")
        for screen in screens {
            let focus = state.screens[screen.id] ?? .hidden
            print("  display \(screen.id):\(String(repeating: " ", count: max(1, 19 - String(screen.id).count))) \(focus.target.map { "overlay below window \($0.targetID)" } ?? "no overlay")")
        }

        // Put a tiny, nearly invisible overlay on screen so AppKit builds its layer tree.
        let probe = OverlayWindow(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        probe.alphaValue = 0.01
        probe.orderFrontRegardless()
        probe.apply(BlurStyle(radius: 24, saturation: 0), force: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        probe.blurView.effect.retune(force: true)
        let effect = probe.blurView.effect
        if effect.hasBackdrop {
            let filters = (effect.backdrop?.filters as? [NSObject])?.compactMap { $0.value(forKey: "name") as? String } ?? []
            print("  blur engine:                tuned backdrop (\(effect.backdropClassName ?? "?")), filters \(filters)")
        } else if PrivateAPI.hasWindowBlur {
            print("  blur engine:                window-server blur (fallback; Monochrome and Ambient falloff unavailable)")
        } else {
            print("  blur engine:                system material only (limited)")
        }

        // The whole design rests on ordering our window directly below another app's window.
        if let targetID = state.focusedWindowID {
            probe.order(.below, relativeTo: Int(targetID))
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let ids = source.snapshot().map(\.id)
            let probeIndex = ids.firstIndex(of: UInt32(probe.windowNumber))
            let targetIndex = ids.firstIndex(of: targetID)
            if let probeIndex, let targetIndex {
                let between = ids[(targetIndex + 1)..<max(probeIndex, targetIndex + 1)].count
                let works = probeIndex > targetIndex && between == 0
                print("  cross-app ordering:         \(works ? "works" : "FAILED (probe at \(probeIndex), target at \(targetIndex))")")
            } else {
                print("  cross-app ordering:         not measurable (window list unavailable)")
            }
        } else {
            print("  cross-app ordering:         skipped (no focused window)")
        }
        probe.orderOut(nil)
        exit(0)
    }
}
