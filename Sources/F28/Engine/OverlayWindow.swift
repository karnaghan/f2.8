import AppKit

/// A borderless, click-through window that blurs whatever is behind it.
final class OverlayWindow: NSWindow {
    let blurView: FocusBlurView
    /// True when the backdrop tuning is unavailable and the window-server blur is used instead.
    private(set) var usesFallbackBlur = false

    init(frame: NSRect, level: NSWindow.Level = .normal) {
        blurView = FocusBlurView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        self.level = level
        // Transient: Mission Control and Exposé hide the overlay instead of drawing over it.
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        alphaValue = 0
        contentView = blurView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(_ style: BlurStyle, force: Bool = false) {
        blurView.apply(style, force: force)
        if usesFallbackBlur { PrivateAPI.setBackgroundBlur(self, radius: style.radius) }
    }

    /// Switch to the window-server blur when the tuned backdrop could not be found.
    /// Returns true if the fallback was engaged.
    @discardableResult
    func engageFallbackIfNeeded() -> Bool {
        blurView.effect.retune(force: true)
        guard !blurView.effect.hasBackdrop, !usesFallbackBlur, PrivateAPI.hasWindowBlur else { return false }
        usesFallbackBlur = true
        blurView.effect.isHidden = true
        PrivateAPI.setBackgroundBlur(self, radius: blurView.style.radius)
        return true
    }
}

/// Converting between Quartz global coordinates (top-left origin) and AppKit (bottom-left origin).
enum ScreenGeometry {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static var primaryHeight: CGFloat { CGDisplayBounds(CGMainDisplayID()).height }

    static func appKitRect(fromQuartz rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
