import AppKit

/// "The dot": a small floating button that toggles focus on click. Drag to move it;
/// right-click for quick options. Shown and hidden with ⌃⌥⌘C.
@MainActor
final class ControlDotController {
    private let prefs: Preferences
    private let panel: NSPanel
    private let dot: DotView

    init(prefs: Preferences, onToggle: @escaping () -> Void, menu: @escaping () -> NSMenu) {
        self.prefs = prefs
        let size = NSSize(width: 38, height: 38)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        dot = DotView(frame: NSRect(origin: .zero, size: size))
        dot.onClick = onToggle
        dot.menuProvider = menu
        dot.onMoved = { [weak prefs, weak panel] in
            guard let panel else { return }
            prefs?.controlDotOrigin = panel.frame.origin
        }
        panel.contentView = dot
        placeInitially()
    }

    var windowID: UInt32 { UInt32(panel.windowNumber) }

    func refresh() {
        dot.isOn = prefs.enabled
        setVisible(prefs.showControls)
    }

    private func setVisible(_ visible: Bool) {
        if visible, !panel.isVisible {
            ensureOnScreen()
            panel.orderFrontRegardless()
        } else if !visible, panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func placeInitially() {
        if let origin = prefs.controlDotOrigin {
            panel.setFrameOrigin(origin)
        } else if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - 64, y: visible.minY + 64))
        }
    }

    private func ensureOnScreen() {
        let frame = panel.frame
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { return }
        prefs.controlDotOrigin = nil
        placeInitially()
    }
}

private final class DotView: NSView {
    var isOn = true { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onMoved: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    private var downPoint: NSPoint?
    private var dragged = false
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "f/2.8 — click to toggle focus, drag to move"
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let ring = bounds.insetBy(dx: 3, dy: 3)
        let body = NSBezierPath(ovalIn: ring)
        NSColor(white: 0.08, alpha: hovering ? 0.82 : 0.7).setFill()
        body.fill()
        NSColor(white: 1, alpha: 0.22).setStroke()
        body.lineWidth = 1
        body.stroke()

        let accent = NSColor(srgbRed: 0.96, green: 0.65, blue: 0.23, alpha: 1)
        let symbol = NSImage(systemSymbolName: isOn ? "camera.aperture" : "circle.dashed", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))
        if let symbol {
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                (self.isOn ? accent : NSColor(white: 0.75, alpha: 1)).set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let origin = NSPoint(x: bounds.midX - symbol.size.width / 2, y: bounds.midY - symbol.size.height / 2)
            tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let downPoint else { return }
        let p = event.locationInWindow
        if hypot(p.x - downPoint.x, p.y - downPoint.y) > 3 {
            dragged = true
            window?.performDrag(with: event)
            onMoved?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { onClick?() }
        downPoint = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
}
