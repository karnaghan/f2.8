import CoreGraphics
import F28Core
import Foundation

// Minimal test harness: the Command Line Tools ship without XCTest, so this runs as a plain executable.
var failures = 0
var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if condition() {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ \(message)  (line \(line))")
    }
}

func suite(_ name: String, _ body: () -> Void) {
    print("\n\(name)")
    body()
}

// MARK: - Fixtures

let left = ScreenInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
let right = ScreenInfo(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))

func win(_ id: UInt32, pid: Int32, _ bundle: String, x: CGFloat = 100, y: CGFloat = 100,
         w: CGFloat = 800, h: CGFloat = 600, layer: Int = 0) -> WindowInfo {
    WindowInfo(id: id, pid: pid, bundleID: bundle, ownerName: bundle, layer: layer,
               bounds: CGRect(x: x, y: y, width: w, height: h))
}

let safari1 = win(11, pid: 100, "com.apple.Safari")
let safari2 = win(12, pid: 100, "com.apple.Safari", x: 300)
let notes1 = win(21, pid: 200, "com.apple.Notes")
let xcode1 = win(31, pid: 300, "com.apple.dt.Xcode")
let claude1 = win(41, pid: 400, "com.anthropic.claudefordesktop")

// MARK: - FocusResolver

suite("FocusResolver – single display") {
    let s = FocusResolver.resolve(windows: [safari1, notes1, safari2], frontPID: 100,
                                  frontBundleID: "com.apple.Safari", screens: [left], options: FocusOptions())
    check(s.focusedWindowID == 11, "focused window is the frontmost app's top window")
    check(s.screens[1] == .focus(ScreenTarget(targetID: 11, sharpIDs: [11])), "overlay sits right below it")

    let wide = FocusResolver.resolve(windows: [safari1, safari2, notes1], frontPID: 100,
                                     frontBundleID: "com.apple.Safari", screens: [left],
                                     options: FocusOptions(appWide: true))
    check(wide.screens[1]?.target?.targetID == 12, "app-wide focus keeps the app's next window sharp")
    check(wide.screens[1]?.target?.sharpIDs == [11, 12], "app-wide sharp set is both Safari windows")

    let interleaved = FocusResolver.resolve(windows: [safari1, notes1, safari2], frontPID: 100,
                                            frontBundleID: "com.apple.Safari", screens: [left],
                                            options: FocusOptions(appWide: true))
    check(interleaved.screens[1]?.target?.targetID == 11, "app-wide run stops at another app's window")
}

suite("FocusResolver – ignore list, groups, filtering") {
    let ignored = FocusResolver.resolve(windows: [safari1, notes1], frontPID: 100, frontBundleID: "com.apple.Safari",
                                        screens: [left], options: FocusOptions(ignoredBundleIDs: ["com.apple.Safari"]))
    check(ignored.screens[1] == .hidden, "ignored frontmost app hides the overlay")
    check(ignored.focusedWindowID == nil, "ignored app reports no focused window")

    let grouped = FocusResolver.resolve(windows: [xcode1, claude1, notes1], frontPID: 300,
                                        frontBundleID: "com.apple.dt.Xcode", screens: [left],
                                        options: FocusOptions(appGroups: [["com.apple.dt.Xcode", "com.anthropic.claudefordesktop"]]))
    check(grouped.screens[1]?.target?.targetID == 41, "app group keeps the paired app sharp")
    check(grouped.screens[1]?.target?.sharpIDs == [31, 41], "group sharp set is Xcode + Claude")

    let reversed = FocusResolver.resolve(windows: [claude1, xcode1, notes1], frontPID: 400,
                                         frontBundleID: "com.anthropic.claudefordesktop", screens: [left],
                                         options: FocusOptions(appGroups: [["com.apple.dt.Xcode", "com.anthropic.claudefordesktop"]]))
    check(reversed.screens[1]?.target?.targetID == 31, "groups work in both directions")

    let menuBar = win(1, pid: 100, "com.apple.Safari", y: 0, w: 1512, h: 30, layer: 25)
    let tiny = win(2, pid: 100, "com.apple.Safari", w: 10, h: 10)
    let filtered = FocusResolver.resolve(windows: [menuBar, tiny, safari1], frontPID: 100,
                                         frontBundleID: "com.apple.Safari", screens: [left], options: FocusOptions())
    check(filtered.focusedWindowID == 11, "non-zero layers and tiny windows are skipped")

    check(filtered.focusIsOnTop, "focus counts as on top when only non-normal windows are above it")
    let midSwitch = FocusResolver.resolve(windows: [notes1, xcode1, safari1], frontPID: 100,
                                          frontBundleID: "com.apple.Safari", screens: [left], options: FocusOptions())
    check(!midSwitch.focusIsOnTop, "app switch in flight: focused window not yet raised is flagged")

    let none = FocusResolver.resolve(windows: [notes1], frontPID: 100, frontBundleID: "com.apple.Safari",
                                     screens: [left], options: FocusOptions())
    check(none.screens[1] == .hidden, "frontmost app without windows hides the overlay")

    let nobody = FocusResolver.resolve(windows: [notes1], frontPID: nil, frontBundleID: nil,
                                       screens: [left], options: FocusOptions())
    check(nobody.screens[1] == .hidden, "no frontmost app hides the overlay")
}

suite("FocusResolver – multiple displays") {
    let onRight1 = win(51, pid: 200, "com.apple.Notes", x: 1700, y: 200)
    let onRight2 = win(52, pid: 500, "com.apple.mail", x: 1900, y: 300)
    let windows = [safari1, onRight1, onRight2]

    let per = FocusResolver.resolve(windows: windows, frontPID: 100, frontBundleID: "com.apple.Safari",
                                    screens: [left, right], options: FocusOptions(multiScreen: .perScreen))
    check(per.activeScreenID == 1, "active display is the one holding the focused window")
    check(per.screens[1]?.target?.targetID == 11, "per-screen: active display focuses Safari")
    check(per.screens[2]?.target?.targetID == 51, "per-screen: other display keeps its topmost window")

    let global = FocusResolver.resolve(windows: windows, frontPID: 100, frontBundleID: "com.apple.Safari",
                                       screens: [left, right], options: FocusOptions(multiScreen: .global))
    check(global.screens[2]?.target?.targetID == 11, "global: other display is blurred below the focused window")

    let ignoredOther = FocusResolver.resolve(windows: windows, frontPID: 100, frontBundleID: "com.apple.Safari",
                                             screens: [left, right],
                                             options: FocusOptions(multiScreen: .perScreen, ignoredBundleIDs: ["com.apple.Notes"]))
    check(ignoredOther.screens[2] == .hidden, "per-screen: display topped by an ignored app is left alone")

    let empty = FocusResolver.resolve(windows: [safari1], frontPID: 100, frontBundleID: "com.apple.Safari",
                                      screens: [left, right], options: FocusOptions(multiScreen: .perScreen))
    check(empty.screens[2] == .hidden, "per-screen: a display with no windows is not blurred")

    let straddle = CGRect(x: 1400, y: 100, width: 100, height: 100) // centre at x=1450, on the left display
    check(FocusResolver.screenID(for: straddle, in: [left, right]) == 1, "window centre decides its display")
    let offscreen = CGRect(x: 1500, y: -400, width: 400, height: 500) // centre above both displays
    check(FocusResolver.screenID(for: offscreen, in: [left, right]) == 2, "largest overlap breaks ties")
}

// MARK: - ShakeDetector

func shake(_ detector: inout ShakeDetector, amplitude: CGFloat, hertz: Double, seconds: Double,
           start: Double = 0, rate: Double = 120) -> Int {
    var fires = 0
    let steps = Int(seconds * rate)
    for i in 0...steps {
        let t = start + Double(i) / rate
        let x = 500 + amplitude * CGFloat(sin(2 * Double.pi * hertz * t))
        if detector.feed(CGPoint(x: x, y: 400), at: t) { fires += 1 }
    }
    return fires
}

suite("ShakeDetector") {
    var d = ShakeDetector(sensitivity: 0.5)
    check(shake(&d, amplitude: 120, hertz: 4, seconds: 0.8) == 1, "a vigorous shake fires once")

    var drift = ShakeDetector(sensitivity: 0.5)
    var driftFires = 0
    for i in 0...120 {
        let t = Double(i) / 120
        if drift.feed(CGPoint(x: 100 + 3 * CGFloat(i), y: 300), at: t) { driftFires += 1 }
    }
    check(driftFires == 0, "a slow straight move does not fire")

    var jitter = ShakeDetector(sensitivity: 1)
    check(shake(&jitter, amplitude: 3, hertz: 12, seconds: 1) == 0, "hand jitter does not fire, even at high sensitivity")

    var cool = ShakeDetector(sensitivity: 0.5)
    check(shake(&cool, amplitude: 120, hertz: 4, seconds: 0.95) == 1, "continued shaking inside the cooldown fires once")
    check(shake(&cool, amplitude: 120, hertz: 4, seconds: 0.8, start: 2.0) == 1, "fires again after the cooldown")

    var high = ShakeDetector(sensitivity: 1)
    var low = ShakeDetector(sensitivity: 0)
    check(shake(&high, amplitude: 25, hertz: 4, seconds: 0.8) >= 1, "high sensitivity accepts a small shake")
    check(shake(&low, amplitude: 25, hertz: 4, seconds: 0.8) == 0, "low sensitivity ignores the same small shake")

    var paused = ShakeDetector(sensitivity: 0.5)
    _ = paused.feed(CGPoint(x: 0, y: 0), at: 0)
    _ = paused.feed(CGPoint(x: 200, y: 0), at: 0.05)
    _ = paused.feed(CGPoint(x: 0, y: 0), at: 0.1)
    _ = paused.feed(CGPoint(x: 200, y: 0), at: 1.0) // long pause resets the gesture
    check(!paused.feed(CGPoint(x: 0, y: 0), at: 1.05), "a pause resets partial shakes")

    check(ShakeDetector(sensitivity: 0).requiredReversals == 5 && ShakeDetector(sensitivity: 1).requiredReversals == 3,
          "sensitivity maps to 5…3 reversals")
}

// MARK: - MaskRenderer

suite("MaskRenderer") {
    let size = CGSize(width: 1600, height: 1000)
    guard let solid = MaskRenderer.image(size: size, holes: [], feather: 0) else {
        check(false, "renders a mask")
        return
    }
    check(MaskRenderer.alpha(of: solid, at: CGPoint(x: 0.5, y: 0.5)) > 0.99, "no holes → fully opaque")

    let hole = CGRect(x: 600, y: 400, width: 400, height: 200)
    guard let soft = MaskRenderer.image(size: size, holes: [MaskHole(hole)], feather: 60, inflate: 30) else {
        check(false, "renders an ambient mask")
        return
    }
    let centre = MaskRenderer.alpha(of: soft, at: CGPoint(x: 0.5, y: 0.5))
    let edge = MaskRenderer.alpha(of: soft, at: CGPoint(x: 0.5, y: 0.66))
    let corner = MaskRenderer.alpha(of: soft, at: CGPoint(x: 0.02, y: 0.02))
    check(centre < 0.1, "hole centre is see-through (\(String(format: "%.2f", centre)))")
    check(edge > centre && edge < corner, "alpha ramps up away from the window (\(String(format: "%.2f", edge)))")
    check(corner > 0.95, "far corner is fully blurred (\(String(format: "%.2f", corner)))")

    guard let topLeft = MaskRenderer.image(size: size, holes: [MaskHole(CGRect(x: 0, y: 0, width: 400, height: 250))], feather: 0) else {
        check(false, "renders an unfeathered mask")
        return
    }
    check(MaskRenderer.alpha(of: topLeft, at: CGPoint(x: 0.05, y: 0.05)) < 0.01, "hole coordinates use a top-left origin")
    check(MaskRenderer.alpha(of: topLeft, at: CGPoint(x: 0.05, y: 0.95)) > 0.99, "bottom-left stays opaque")

    guard let partial = MaskRenderer.image(size: size, holes: [MaskHole(hole, alpha: 0.4)], feather: 0) else {
        check(false, "renders a partial hole")
        return
    }
    let mid = MaskRenderer.alpha(of: partial, at: CGPoint(x: 0.5, y: 0.5))
    check(abs(mid - 0.4) < 0.02, "partial holes keep their alpha (\(String(format: "%.2f", mid)))")
}

print("\n\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
