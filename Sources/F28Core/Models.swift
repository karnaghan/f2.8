import CoreGraphics

/// One on-screen window, as reported by `CGWindowListCopyWindowInfo` (front-to-back order).
/// `bounds` uses Quartz global coordinates: origin at the top-left of the primary display.
public struct WindowInfo: Equatable, Sendable {
    public var id: UInt32
    public var pid: Int32
    public var bundleID: String?
    public var ownerName: String?
    public var layer: Int
    public var bounds: CGRect
    public var alpha: Double

    public init(id: UInt32, pid: Int32, bundleID: String? = nil, ownerName: String? = nil,
                layer: Int = 0, bounds: CGRect, alpha: Double = 1) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.ownerName = ownerName
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
    }
}

/// A display, with its frame in the same Quartz global coordinates as `WindowInfo.bounds`.
public struct ScreenInfo: Equatable, Sendable {
    public var id: UInt32
    public var frame: CGRect

    public init(id: UInt32, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public enum MultiScreenMode: String, CaseIterable, Sendable {
    /// Each display keeps its own sharp window (the one you used last there).
    case perScreen
    /// Only the focused window is sharp; every other display is fully blurred.
    case global
}

public struct FocusOptions: Equatable, Sendable {
    public var appWide: Bool
    public var multiScreen: MultiScreenMode
    public var ignoredBundleIDs: Set<String>
    public var appGroups: [[String]]
    public var minimumWindowSide: CGFloat

    public init(appWide: Bool = false, multiScreen: MultiScreenMode = .perScreen,
                ignoredBundleIDs: Set<String> = [], appGroups: [[String]] = [],
                minimumWindowSide: CGFloat = 40) {
        self.appWide = appWide
        self.multiScreen = multiScreen
        self.ignoredBundleIDs = ignoredBundleIDs
        self.appGroups = appGroups
        self.minimumWindowSide = minimumWindowSide
    }
}

/// Where a display's overlay should sit in the window stack.
public struct ScreenTarget: Equatable, Sendable {
    /// The overlay is ordered directly below this window.
    public var targetID: UInt32
    /// Windows that end up above the overlay (front-to-back, ending with `targetID`).
    public var sharpIDs: [UInt32]

    public init(targetID: UInt32, sharpIDs: [UInt32]) {
        self.targetID = targetID
        self.sharpIDs = sharpIDs
    }
}

public enum ScreenFocus: Equatable, Sendable {
    case hidden
    case focus(ScreenTarget)

    public var target: ScreenTarget? {
        if case let .focus(t) = self { return t }
        return nil
    }
}

public struct FocusState: Equatable, Sendable {
    public var focusedWindowID: UInt32?
    public var activeScreenID: UInt32?
    public var screens: [UInt32: ScreenFocus]
    /// False while another app's window is still stacked above the focused one — typically
    /// the instant after an app switch, before the window server has raised its window.
    public var focusIsOnTop: Bool

    public init(focusedWindowID: UInt32? = nil, activeScreenID: UInt32? = nil,
                screens: [UInt32: ScreenFocus] = [:], focusIsOnTop: Bool = true) {
        self.focusedWindowID = focusedWindowID
        self.activeScreenID = activeScreenID
        self.screens = screens
        self.focusIsOnTop = focusIsOnTop
    }

    public static let empty = FocusState()
}
