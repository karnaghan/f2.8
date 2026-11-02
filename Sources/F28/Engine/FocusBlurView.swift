import AppKit
import QuartzCore

/// The look of the overlay, fully resolved from preferences.
struct BlurStyle: Equatable {
    var radius: CGFloat = 30
    var saturation: CGFloat = 1
    var tint: NSColor?
    var dim: CGFloat = 0
    var grain: CGFloat = 0
}

/// A behind-window blur whose radius and saturation can be set freely.
///
/// AppKit's `NSVisualEffectView` does the hard part (a window-server-aware `CABackdropLayer`
/// that samples everything behind the window). We then swap the backdrop's filters for our
/// own blur + saturation pair and mute the material's tint layers so only the blur remains.
final class TunedEffectView: NSVisualEffectView {
    private(set) var radius: CGFloat = 30
    private(set) var saturation: CGFloat = 1
    private(set) weak var backdrop: CALayer?
    private(set) var backdropClassName: String?
    private var applied: (layer: ObjectIdentifier, radius: CGFloat, saturation: CGFloat)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        blendingMode = .behindWindow
        material = .fullScreenUI
        state = .active
        isEmphasized = false
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var hasBackdrop: Bool { backdrop != nil }

    func tune(radius: CGFloat, saturation: CGFloat) {
        self.radius = radius
        self.saturation = saturation
        retune(force: false)
    }

    override func layout() { super.layout(); retune(force: false) }
    override func updateLayer() { super.updateLayer(); retune(force: true) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); retune(force: true) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); retune(force: true) }

    /// Animate the blur radius ("focus pull"). The model value stays at `to`.
    func animateRadius(from: CGFloat, to: CGFloat, duration: CFTimeInterval) {
        guard let backdrop, hasOurFilters(backdrop) else { return }
        let animation = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        backdrop.add(animation, forKey: "focusPull")
    }

    func retune(force: Bool) {
        guard let root = layer, let found = Self.findBackdrop(in: root) else {
            backdrop = nil
            return
        }
        backdrop = found
        backdropClassName = NSStringFromClass(type(of: found))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        Self.muteMaterial(root: root, keeping: found)

        let key = (ObjectIdentifier(found), radius, saturation)
        if !force, let applied, applied == key, hasOurFilters(found) { return }
        var filters: [NSObject] = []
        if let blur = PrivateAPI.filter("gaussianBlur", name: "gaussianBlur") {
            blur.setValue(radius, forKey: "inputRadius")
            blur.setValue(true, forKey: "inputNormalizeEdges")
            filters.append(blur)
        }
        if let saturate = PrivateAPI.filter("colorSaturate", name: "colorSaturate") {
            saturate.setValue(saturation, forKey: "inputAmount")
            filters.append(saturate)
        }
        guard !filters.isEmpty else { return }
        found.filters = filters
        applied = key
    }

    private func hasOurFilters(_ layer: CALayer) -> Bool {
        guard let first = layer.filters?.first as? NSObject else { return false }
        return (first.value(forKey: "name") as? String) == "gaussianBlur"
    }

    private static func findBackdrop(in layer: CALayer) -> CALayer? {
        if NSStringFromClass(type(of: layer)).contains("Backdrop") { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let hit = findBackdrop(in: sublayer) { return hit }
        }
        return nil
    }

    /// Hide every material layer (tint, vibrancy fill, highlights) except the backdrop and its ancestors.
    private static func muteMaterial(root: CALayer, keeping backdrop: CALayer) {
        var path = Set<ObjectIdentifier>()
        var cursor: CALayer? = backdrop
        while let layer = cursor {
            path.insert(ObjectIdentifier(layer))
            cursor = layer.superlayer
        }
        func visit(_ layer: CALayer) {
            for sublayer in layer.sublayers ?? [] {
                if sublayer === backdrop { continue }
                if path.contains(ObjectIdentifier(sublayer)) {
                    visit(sublayer)
                } else if sublayer.opacity != 0 {
                    sublayer.opacity = 0
                }
            }
        }
        visit(root)
    }
}

/// Tint, dimming and film grain drawn on top of the blur.
private final class FilmView: NSView {
    private let tintLayer = CALayer()
    private let dimLayer = CALayer()
    private let grainLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for sublayer in [tintLayer, dimLayer, grainLayer] {
            sublayer.isHidden = true
            layer?.addSublayer(sublayer)
        }
        grainLayer.backgroundColor = Grain.patternColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sublayer in [tintLayer, dimLayer, grainLayer] { sublayer.frame = bounds }
        CATransaction.commit()
    }

    func apply(tint: NSColor?, dim: CGFloat, grain: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.backgroundColor = tint?.cgColor
        tintLayer.isHidden = tint == nil
        dimLayer.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
        dimLayer.isHidden = dim <= 0.001
        grainLayer.opacity = Float(grain)
        grainLayer.isHidden = grain <= 0.001
        CATransaction.commit()
    }
}

/// Blur + film, filling an overlay window.
final class FocusBlurView: NSView {
    let effect: TunedEffectView
    private let film: FilmView
    private(set) var style = BlurStyle()

    override init(frame frameRect: NSRect) {
        let local = NSRect(origin: .zero, size: frameRect.size)
        effect = TunedEffectView(frame: local)
        film = FilmView(frame: local)
        super.init(frame: frameRect)
        wantsLayer = true
        effect.autoresizingMask = [.width, .height]
        film.autoresizingMask = [.width, .height]
        addSubview(effect)
        addSubview(film)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ newStyle: BlurStyle, force: Bool = false) {
        guard force || newStyle != style else { return }
        style = newStyle
        effect.tune(radius: newStyle.radius, saturation: newStyle.saturation)
        film.apply(tint: newStyle.tint, dim: newStyle.dim, grain: newStyle.grain)
    }
}

/// A tiling noise texture for the grain layer, generated once.
enum Grain {
    static let patternColor: CGColor = {
        let side = 192
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data
        else { return NSColor.clear.cgColor }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<(side * side) {
            let alpha = UInt8.random(in: 0...90, using: &rng)
            let value: UInt8 = Bool.random(using: &rng) ? alpha : 0 // premultiplied white or black speck
            pixels[i * 4] = value
            pixels[i * 4 + 1] = value
            pixels[i * 4 + 2] = value
            pixels[i * 4 + 3] = alpha
        }
        guard let image = ctx.makeImage() else { return NSColor.clear.cgColor }
        // Half-size in points so each speck is one physical pixel on Retina displays.
        let tile = NSImage(cgImage: image, size: NSSize(width: side / 2, height: side / 2))
        return NSColor(patternImage: tile).cgColor
    }()
}
