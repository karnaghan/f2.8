import AppKit
import Combine
import F28Core

enum FocusMode: String, CaseIterable, Identifiable {
    case deep, ambient
    var id: String { rawValue }
    var title: String { self == .deep ? "Deep" : "Ambient" }
    var blurb: String {
        switch self {
        case .deep: return "Blurs everything behind your window, edge to edge."
        case .ambient: return "A softer, graduated blur that falls off around your window."
        }
    }
    var next: FocusMode { self == .deep ? .ambient : .deep }
}

enum TintStyle: String, CaseIterable, Identifiable {
    case system, light, dark, custom, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "As System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .custom: return "Custom"
        case .none: return "None"
        }
    }
}

enum RevealEffect: String, CaseIterable, Identifiable {
    case fade, focusPull, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fade: return "Fade"
        case .focusPull: return "Focus Pull"
        case .none: return "None"
        }
    }
}

extension MultiScreenMode {
    var title: String { self == .perScreen ? "Per screen" : "Global" }
    var blurb: String {
        switch self {
        case .perScreen: return "Each display keeps the window you used last there."
        case .global: return "Only your focused window is sharp; other displays blur fully."
        }
    }
}

/// Every user setting, persisted to `UserDefaults` as it changes.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let enabled = "enabled"
        static let mode = "mode"
        static let blur = "blur"
        static let tint = "tint"
        static let customTint = "customTint"
        static let dim = "dim"
        static let grain = "grain"
        static let monochrome = "monochrome"
        static let reveal = "revealEffect"
        static let duration = "transitionDuration"
        static let appWide = "appWide"
        static let multiScreen = "multiScreen"
        static let stageManager = "blurStageManager"
        static let autoHideBars = "autoHideBars"
        static let shakeToggle = "shakeToToggle"
        static let shakePeek = "shakeToPeek"
        static let sensitivity = "shakeSensitivity"
        static let showControls = "showControls"
        static let showInDock = "showInDock"
        static let ignored = "ignoredApps"
        static let groups = "appGroups"
        static let launched = "hasLaunchedBefore"
        static let dotOrigin = "controlDotOrigin"
    }

    private let store: UserDefaults

    @Published var enabled: Bool { didSet { store.set(enabled, forKey: Key.enabled) } }
    @Published var mode: FocusMode { didSet { store.set(mode.rawValue, forKey: Key.mode) } }
    @Published var blur: Double { didSet { store.set(blur, forKey: Key.blur) } }
    @Published var tint: TintStyle { didSet { store.set(tint.rawValue, forKey: Key.tint) } }
    @Published var customTintHex: String { didSet { store.set(customTintHex, forKey: Key.customTint) } }
    @Published var dim: Double { didSet { store.set(dim, forKey: Key.dim) } }
    @Published var grain: Double { didSet { store.set(grain, forKey: Key.grain) } }
    @Published var monochrome: Bool { didSet { store.set(monochrome, forKey: Key.monochrome) } }
    @Published var revealEffect: RevealEffect { didSet { store.set(revealEffect.rawValue, forKey: Key.reveal) } }
    @Published var transitionDuration: Double { didSet { store.set(transitionDuration, forKey: Key.duration) } }
    @Published var appWide: Bool { didSet { store.set(appWide, forKey: Key.appWide) } }
    @Published var multiScreen: MultiScreenMode { didSet { store.set(multiScreen.rawValue, forKey: Key.multiScreen) } }
    @Published var blurStageManager: Bool { didSet { store.set(blurStageManager, forKey: Key.stageManager) } }
    @Published var autoHideBars: Bool { didSet { store.set(autoHideBars, forKey: Key.autoHideBars) } }
    @Published var shakeToToggle: Bool { didSet { store.set(shakeToToggle, forKey: Key.shakeToggle) } }
    @Published var shakeToPeek: Bool { didSet { store.set(shakeToPeek, forKey: Key.shakePeek) } }
    @Published var shakeSensitivity: Double { didSet { store.set(shakeSensitivity, forKey: Key.sensitivity) } }
    @Published var showControls: Bool { didSet { store.set(showControls, forKey: Key.showControls) } }
    @Published var showInDock: Bool { didSet { store.set(showInDock, forKey: Key.showInDock) } }
    @Published var ignoredApps: [String] { didSet { store.set(ignoredApps, forKey: Key.ignored) } }
    @Published var appGroups: [[String]] { didSet { store.set(appGroups, forKey: Key.groups) } }

    init(store: UserDefaults = .standard) {
        self.store = store
        store.register(defaults: [
            Key.enabled: true,
            Key.mode: FocusMode.deep.rawValue,
            Key.blur: 0.55,
            Key.tint: TintStyle.system.rawValue,
            Key.customTint: "#5B6CFF",
            Key.dim: 0.15,
            Key.grain: 0.25,
            Key.monochrome: false,
            Key.reveal: RevealEffect.fade.rawValue,
            Key.duration: 0.35,
            Key.appWide: false,
            Key.multiScreen: MultiScreenMode.perScreen.rawValue,
            Key.stageManager: false,
            Key.autoHideBars: false,
            Key.shakeToggle: true,
            Key.shakePeek: true,
            Key.sensitivity: 0.5,
            Key.showControls: false,
            Key.showInDock: true,
        ])
        enabled = store.bool(forKey: Key.enabled)
        mode = FocusMode(rawValue: store.string(forKey: Key.mode) ?? "") ?? .deep
        blur = store.double(forKey: Key.blur)
        tint = TintStyle(rawValue: store.string(forKey: Key.tint) ?? "") ?? .system
        customTintHex = store.string(forKey: Key.customTint) ?? "#5B6CFF"
        dim = store.double(forKey: Key.dim)
        grain = store.double(forKey: Key.grain)
        monochrome = store.bool(forKey: Key.monochrome)
        revealEffect = RevealEffect(rawValue: store.string(forKey: Key.reveal) ?? "") ?? .fade
        transitionDuration = store.double(forKey: Key.duration)
        appWide = store.bool(forKey: Key.appWide)
        multiScreen = MultiScreenMode(rawValue: store.string(forKey: Key.multiScreen) ?? "") ?? .perScreen
        blurStageManager = store.bool(forKey: Key.stageManager)
        autoHideBars = store.bool(forKey: Key.autoHideBars)
        shakeToToggle = store.bool(forKey: Key.shakeToggle)
        shakeToPeek = store.bool(forKey: Key.shakePeek)
        shakeSensitivity = store.double(forKey: Key.sensitivity)
        showControls = store.bool(forKey: Key.showControls)
        showInDock = store.bool(forKey: Key.showInDock)
        ignoredApps = store.stringArray(forKey: Key.ignored) ?? []
        appGroups = (store.array(forKey: Key.groups) as? [[String]]) ?? []
    }

    var hasLaunchedBefore: Bool {
        get { store.bool(forKey: Key.launched) }
        set { store.set(newValue, forKey: Key.launched) }
    }

    var controlDotOrigin: NSPoint? {
        get {
            guard let raw = store.string(forKey: Key.dotOrigin) else { return nil }
            let point = NSPointFromString(raw)
            return point == .zero ? nil : point
        }
        set { store.set(newValue.map(NSStringFromPoint), forKey: Key.dotOrigin) }
    }

    var customTint: NSColor {
        get { NSColor(hex: customTintHex) ?? .systemIndigo }
        set { customTintHex = newValue.hexString }
    }

    var focusOptions: FocusOptions {
        FocusOptions(appWide: appWide, multiScreen: multiScreen,
                     ignoredBundleIDs: Set(ignoredApps), appGroups: appGroups)
    }

    func isIgnored(_ bundleID: String) -> Bool { ignoredApps.contains(bundleID) }

    func toggleIgnored(_ bundleID: String) {
        if let index = ignoredApps.firstIndex(of: bundleID) {
            ignoredApps.remove(at: index)
        } else {
            ignoredApps.append(bundleID)
        }
    }

    func addGroup(_ a: String, _ b: String) {
        guard a != b else { return }
        let pair = [a, b]
        guard !appGroups.contains(where: { Set($0) == Set(pair) }) else { return }
        appGroups.append(pair)
    }

    func resetLook() {
        mode = .deep
        blur = 0.55
        tint = .system
        dim = 0.15
        grain = 0.25
        monochrome = false
        revealEffect = .fade
        transitionDuration = 0.35
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#5B6CFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
