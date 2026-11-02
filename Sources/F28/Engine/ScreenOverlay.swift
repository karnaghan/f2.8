import AppKit
import F28Core

/// The overlay for one display: positions it in the window stack, fades it, and drives
/// the Ambient gradient mask and the reveal transition.
@MainActor
final class ScreenOverlay {
    struct Context {
        /// Every on-screen window front-to-back, f/2.8's own included.
        let windows: [WindowInfo]
        /// Foreign windows by ID.
        let byID: [UInt32: WindowInfo]
        /// f/2.8's own overlay window IDs.
        let ours: Set<UInt32>
        let reveal: RevealEffect
        let duration: TimeInterval
        let fadeDuration: TimeInterval
    }

    let displayID: CGDirectDisplayID
    private(set) var frame: CGRect // Quartz global coordinates
    let window: OverlayWindow
    private var stripWindow: OverlayWindow?

    private(set) var isShown = false
    private(set) var target: ScreenTarget?
    private var sharpRects: [CGRect] = [] // overlay-local, top-left origin
    private var style = BlurStyle()
    private var mode: FocusMode = .deep
    private var peeking = false
    private var alphaGoal: CGFloat = 0
    private var maskLayer: CALayer?
    private var transitionToken = 0
    private var isTransitioning = false
    private var engineChecked = false

    init(displayID: CGDirectDisplayID, frame: CGRect, style: BlurStyle, mode: FocusMode) {
        self.displayID = displayID
        self.frame = frame
        self.style = style
        self.mode = mode
        window = OverlayWindow(frame: ScreenGeometry.appKitRect(fromQuartz: frame))
        window.apply(style, force: true)
    }

    var windowIDs: [UInt32] {
        var ids = [UInt32(window.windowNumber)]
        if let stripWindow { ids.append(UInt32(stripWindow.windowNumber)) }
        return ids
    }

    var usesFallbackBlur: Bool { window.usesFallbackBlur }
    var backdropClassName: String? { window.blurView.effect.backdropClassName }

    // MARK: - Configuration

    func updateFrame(_ newFrame: CGRect) {
        guard newFrame != frame else { return }
        frame = newFrame
        window.setFrame(ScreenGeometry.appKitRect(fromQuartz: newFrame), display: true)
        maskLayer?.frame = window.blurView.bounds
        refreshMask()
    }

    func apply(style newStyle: BlurStyle, mode newMode: FocusMode) {
        style = newStyle
        window.apply(newStyle)
        stripWindow?.apply(newStyle)
        guard newMode != mode else { return }
        let old = mode
        mode = newMode
        guard isShown else { refreshMask(); return }
        // Cross-fade between the flat Deep mask and the Ambient gradient.
        let from = old == .ambient ? ambientImage() : solidImage()
        let to = newMode == .ambient ? ambientImage() : solidImage()
        animateMask(from: from, to: to, duration: 0.35)
    }

    func setPeeking(_ on: Bool, duration: TimeInterval) {
        peeking = on
        guard isShown else { return }
        fade(to: on ? 0 : 1, duration: duration)
    }

    func tearDown() {
        window.orderOut(nil)
        stripWindow?.orderOut(nil)
        isShown = false
    }

    // MARK: - Per-tick update

    func update(_ focus: ScreenFocus, context ctx: Context) {
        guard case let .focus(newTarget) = focus else {
            hide(duration: ctx.fadeDuration)
            return
        }
        let rects = localRects(for: newTarget.sharpIDs, in: ctx)

        if !isShown {
            isShown = true
            target = newTarget
            sharpRects = rects
            window.order(.below, relativeTo: Int(newTarget.targetID))
            refreshMask()
            fade(to: peeking ? 0 : 1, duration: ctx.fadeDuration)
            checkEngineSoon()
            return
        }

        let previous = target
        target = newTarget
        let rectsChanged = rects != sharpRects
        sharpRects = rects
        guard needsReorder(below: newTarget.targetID, ctx) else {
            if rectsChanged && mode == .ambient && !isTransitioning { refreshMask() }
            return
        }

        // Windows that were sharp and are about to slip under the overlay.
        let leaving = (previous?.sharpIDs ?? [])
            .filter { !newTarget.sharpIDs.contains($0) }
            .compactMap { ctx.byID[$0]?.bounds }
            .filter { $0.intersects(frame) }
            .map(local)

        if leaving.isEmpty || ctx.reveal == .none || ctx.duration <= 0.01 {
            window.order(.below, relativeTo: Int(newTarget.targetID))
            if !isTransitioning { refreshMask() }
            return
        }

        // Reveal: punch see-through holes where the old windows are *before* reordering,
        // so they never flash blurred, then let the holes close.
        let fromImage = holedImage(extra: leaving)
        let toImage = mode == .ambient ? ambientImage() : solidImage()
        setMaskImmediately(fromImage)
        CATransaction.flush()
        window.order(.below, relativeTo: Int(newTarget.targetID))
        animateMask(from: fromImage, to: toImage, duration: ctx.duration)
        if ctx.reveal == .focusPull {
            window.blurView.effect.animateRadius(from: style.radius * 0.25, to: style.radius, duration: ctx.duration * 1.4)
        }
    }

    /// Stage Manager draws its strip of thumbnails above normal windows; cover it with a
    /// second overlay at a matching level.
    func updateStageManager(_ stageWindows: [WindowInfo]) {
        let screenArea = frame.width * frame.height
        let mine = stageWindows.filter {
            $0.bounds.intersects(frame) && $0.bounds.width * $0.bounds.height < screenArea * 0.5
        }
        guard isShown, !mine.isEmpty, let level = mine.map(\.layer).max() else {
            stripWindow?.orderOut(nil)
            return
        }
        let union = mine.reduce(CGRect.null) { $0.union($1.bounds) }.intersection(frame)
        let strip = stripWindow ?? makeStripWindow()
        strip.level = NSWindow.Level(rawValue: level + 1)
        let appKitFrame = ScreenGeometry.appKitRect(fromQuartz: union.insetBy(dx: -6, dy: -6))
        if strip.frame != appKitFrame { strip.setFrame(appKitFrame, display: false) }
        if !strip.isVisible {
            strip.alphaValue = alphaGoal
            strip.orderFrontRegardless()
            if window.usesFallbackBlur { strip.engageFallbackIfNeeded() }
        }
    }

    // MARK: - Visibility

    func hide(duration: TimeInterval) {
        guard isShown else { return }
        isShown = false
        target = nil
        sharpRects = []
        fade(to: 0, duration: duration) { [weak self] in
            guard let self, !self.isShown else { return }
            self.window.orderOut(nil)
            self.stripWindow?.orderOut(nil)
        }
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
        alphaGoal = alpha
        let windows = [window] + (stripWindow.map { [$0] } ?? [])
        guard duration > 0.01 else {
            windows.forEach { $0.alphaValue = alpha }
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            windows.forEach { $0.animator().alphaValue = alpha }
        }, completionHandler: {
            MainActor.assumeIsolated { completion?() }
        })
    }

    private func checkEngineSoon() {
        guard !engineChecked else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.engineChecked, self.window.isVisible else { return }
                self.engineChecked = true
                if self.window.engageFallbackIfNeeded() {
                    NSLog("f/2.8: tuned backdrop unavailable, using window-server blur")
                }
            }
        }
    }

    private func makeStripWindow() -> OverlayWindow {
        let strip = OverlayWindow(frame: .zero, level: .floating)
        strip.apply(style, force: true)
        stripWindow = strip
        return strip
    }

    // MARK: - Stack order

    /// True when the overlay is not directly below `targetID`: a foreign normal window sits
    /// between them, or the target slipped below the overlay.
    private func needsReorder(below targetID: UInt32, _ ctx: Context) -> Bool {
        let myID = UInt32(window.windowNumber)
        guard let mine = ctx.windows.firstIndex(where: { $0.id == myID }),
              let theirs = ctx.windows.firstIndex(where: { $0.id == targetID }) else { return true }
        if theirs > mine { return true }
        guard theirs + 1 < mine else { return false }
        return ctx.windows[(theirs + 1)..<mine].contains {
            $0.layer == 0 && $0.alpha > 0 && !ctx.ours.contains($0.id)
        }
    }

    // MARK: - Masks

    private func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -frame.minX, dy: -frame.minY) }

    private func localRects(for ids: [UInt32], in ctx: Context) -> [CGRect] {
        ids.compactMap { ctx.byID[$0]?.bounds }.filter { $0.intersects(frame) }.map(local)
    }

    private var ambientFeather: CGFloat { min(frame.width, frame.height) * 0.16 }

    private func ambientImage() -> CGImage? {
        MaskRenderer.image(size: frame.size, holes: sharpRects.map { MaskHole($0) },
                           feather: ambientFeather, inflate: ambientFeather * 0.9)
    }

    private func solidImage() -> CGImage? {
        MaskRenderer.image(size: frame.size, holes: [], feather: 0)
    }

    /// The steady mask with extra fully see-through holes (used to start a reveal).
    private func holedImage(extra: [CGRect]) -> CGImage? {
        if mode == .ambient {
            return MaskRenderer.image(size: frame.size, holes: (sharpRects + extra).map { MaskHole($0) },
                                      feather: ambientFeather, inflate: ambientFeather * 0.9)
        }
        return MaskRenderer.image(size: frame.size, holes: extra.map { MaskHole($0) }, feather: 5, scale: 0.25)
    }

    private func ensureMaskLayer() -> CALayer {
        if let maskLayer { return maskLayer }
        let layer = CALayer()
        layer.contentsGravity = .resize
        layer.frame = window.blurView.bounds
        window.blurView.layer?.mask = layer
        maskLayer = layer
        return layer
    }

    private func removeMask() {
        window.blurView.layer?.mask = nil
        maskLayer = nil
    }

    private func setMaskImmediately(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ensureMaskLayer().contents = image
        CATransaction.commit()
    }

    /// Bring the mask in line with the current mode and sharp windows, without animation.
    private func refreshMask() {
        guard !isTransitioning else { return }
        if mode == .ambient {
            setMaskImmediately(ambientImage())
        } else {
            removeMask()
        }
    }

    private func animateMask(from: CGImage?, to: CGImage?, duration: TimeInterval) {
        transitionToken &+= 1
        let token = transitionToken
        isTransitioning = true
        let layer = ensureMaskLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.transitionToken == token else { return }
                    self.isTransitioning = false
                    self.refreshMask()
                }
            }
        }
        let animation = CABasicAnimation(keyPath: "contents")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.contents = to
        layer.add(animation, forKey: "reveal")
        CATransaction.commit()
    }
}
