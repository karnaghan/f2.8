import CoreGraphics
import Foundation

/// A region of the overlay that should be (partly) see-through. `alpha` is the overlay
/// opacity left inside the hole: 0 = fully sharp, 1 = fully blurred.
public struct MaskHole: Equatable, Sendable {
    public var rect: CGRect
    public var alpha: CGFloat

    public init(_ rect: CGRect, alpha: CGFloat = 0) {
        self.rect = rect
        self.alpha = alpha
    }
}

/// Renders the alpha masks used for Ambient mode's graduated blur and for reveal transitions.
///
/// Masks are smooth, so they render at a fraction of screen resolution on the CPU
/// (a few hundred pixels across) and the layer scales them up. A triple box blur
/// approximates the Gaussian falloff without needing CoreImage or the GPU.
public enum MaskRenderer {
    public static let defaultScale: CGFloat = 0.125

    /// - Parameters:
    ///   - size: overlay size in points.
    ///   - holes: rects in points, top-left origin, relative to the overlay (like `CGWindow` bounds).
    ///   - feather: Gaussian sigma in points used to soften the edges.
    ///   - inflate: grows every hole by this many points before feathering.
    ///   - scale: render resolution relative to points.
    public static func image(size: CGSize, holes: [MaskHole], feather: CGFloat,
                             inflate: CGFloat = 0, scale: CGFloat = defaultScale) -> CGImage? {
        let width = max(Int((size.width * scale).rounded(.up)), 1)
        let height = max(Int((size.height * scale).rounded(.up)), 1)
        var alpha = [Float](repeating: 1, count: width * height)

        for hole in holes {
            let r = hole.rect.insetBy(dx: -inflate, dy: -inflate)
            let x0 = clamp(Int((r.minX * scale).rounded()), 0, width)
            let x1 = clamp(Int((r.maxX * scale).rounded()), 0, width)
            let y0 = clamp(Int((r.minY * scale).rounded()), 0, height)
            let y1 = clamp(Int((r.maxY * scale).rounded()), 0, height)
            guard x1 > x0, y1 > y0 else { continue }
            let value = Float(min(max(hole.alpha, 0), 1))
            for y in y0..<y1 {
                let row = y * width
                for x in x0..<x1 { alpha[row + x] = value }
            }
        }

        let sigma = feather * scale
        if sigma > 0.05 {
            // Three box passes ≈ Gaussian: (2r+1)² = 4σ² + 1.
            let radius = max(1, Int(((sqrt(4 * sigma * sigma + 1) - 1) / 2).rounded()))
            var scratch = [Float](repeating: 0, count: alpha.count)
            for _ in 0..<3 {
                boxBlur(&alpha, into: &scratch, width: width, height: height, radius: radius, horizontal: true)
                boxBlur(&scratch, into: &alpha, width: width, height: height, radius: radius, horizontal: false)
            }
        }
        return makeImage(alpha, width: width, height: height)
    }

    /// Alpha (0...1) of `image` at a normalised point with a top-left origin. Used by tests.
    public static func alpha(of image: CGImage, at point: CGPoint) -> CGFloat {
        let width = image.width, height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data
        else { return -1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x = clamp(Int(point.x * CGFloat(width)), 0, width - 1)
        let row = clamp(Int(point.y * CGFloat(height)), 0, height - 1) // memory rows run top-down
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return CGFloat(pixels[row * width * 4 + x * 4 + 3]) / 255
    }

    // MARK: - Internals

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

    /// Running-sum box blur with clamped edges.
    private static func boxBlur(_ src: inout [Float], into dst: inout [Float], width: Int, height: Int,
                                radius: Int, horizontal: Bool) {
        let lines = horizontal ? height : width
        let length = horizontal ? width : height
        let stride = horizontal ? 1 : width
        let norm = 1 / Float(2 * radius + 1)
        for line in 0..<lines {
            let base = horizontal ? line * width : line
            @inline(__always) func at(_ i: Int) -> Float { src[base + clamp(i, 0, length - 1) * stride] }
            var sum: Float = 0
            for i in -radius...radius { sum += at(i) }
            for i in 0..<length {
                dst[base + i * stride] = sum * norm
                sum += at(i + radius + 1) - at(i - radius)
            }
        }
    }

    private static func makeImage(_ alpha: [Float], width: Int, height: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let v = UInt8(min(max(alpha[i], 0), 1) * 255 + 0.5)
            // Premultiplied white: every channel equals alpha.
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = v
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
