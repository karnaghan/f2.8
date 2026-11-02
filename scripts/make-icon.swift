// Renders the f/2.8 app icon — a six-blade lens aperture — into an .iconset folder.
// Usage: make-icon <output.iconset>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ stops: [(UInt32, CGFloat)], alpha: CGFloat = 1) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { color($0.0, alpha) } as CFArray,
               locations: stops.map(\.1))!
}

func point(_ c: CGPoint, _ r: CGFloat, _ degrees: CGFloat) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
}

func render(_ pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    // Body: macOS icon grid squircle (824pt on a 1024 canvas).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x141416))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0x3A3A40, 0), (0x16161A, 0.55), (0x0B0B0D, 1)]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    let c = CGPoint(x: 512, y: 512)

    // Lens barrel.
    ctx.addEllipse(in: CGRect(x: c.x - 338, y: c.y - 338, width: 676, height: 676))
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0x6A6A72, 0), (0x2A2A30, 0.5), (0x18181C, 1)]),
                           start: CGPoint(x: 300, y: 860), end: CGPoint(x: 720, y: 160), options: [])
    ctx.resetClip()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Knurled grip ticks.
    ctx.setStrokeColor(color(0x0E0E10, 0.9))
    ctx.setLineWidth(5)
    for i in 0..<90 {
        let angle = CGFloat(i) * 4
        ctx.move(to: point(c, 312, angle))
        ctx.addLine(to: point(c, 334, angle))
    }
    ctx.strokePath()

    // Amber ring.
    ctx.setStrokeColor(color(0xF5A63B))
    ctx.setLineWidth(9)
    ctx.addEllipse(in: CGRect(x: c.x - 298, y: c.y - 298, width: 596, height: 596))
    ctx.strokePath()

    // Iris: six blades around a hexagonal opening.
    let outer: CGFloat = 288
    let inner: CGFloat = 122
    let rotation: CGFloat = 18
    let vertices = (0..<6).map { point(c, inner, CGFloat($0) * 60 + rotation) }
    func exitPoint(from a: CGPoint, through b: CGPoint) -> CGPoint {
        let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let length = hypot(d.x, d.y)
        let u = CGPoint(x: d.x / length, y: d.y / length)
        let p = CGPoint(x: a.x - c.x, y: a.y - c.y)
        let dot = p.x * u.x + p.y * u.y
        let t = -dot + sqrt(dot * dot - (p.x * p.x + p.y * p.y - outer * outer))
        return CGPoint(x: a.x + u.x * t, y: a.y + u.y * t)
    }
    let exits = (0..<6).map { exitPoint(from: vertices[$0], through: vertices[($0 + 1) % 6]) }
    let bladeShades: [(UInt32, UInt32)] = [(0x34343B, 0x1C1C21), (0x2C2C33, 0x17171B), (0x3B3B43, 0x202026)]
    for i in 0..<6 {
        let apex = vertices[i]
        let start = exits[i]
        let end = exits[(i + 5) % 6]
        let blade = CGMutablePath()
        blade.move(to: apex)
        blade.addLine(to: start)
        let a0 = atan2(start.y - c.y, start.x - c.x)
        var a1 = atan2(end.y - c.y, end.x - c.x)
        var delta = a1 - a0
        while delta > .pi { delta -= 2 * .pi }
        while delta <= -.pi { delta += 2 * .pi }
        a1 = a0 + delta
        for step in 1...24 {
            let a = a0 + (a1 - a0) * CGFloat(step) / 24
            blade.addLine(to: CGPoint(x: c.x + outer * cos(a), y: c.y + outer * sin(a)))
        }
        blade.closeSubpath()
        ctx.saveGState()
        ctx.addPath(blade)
        ctx.clip()
        let shade = bladeShades[i % 3]
        ctx.drawLinearGradient(gradient([(shade.0, 0), (shade.1, 1)]),
                               start: apex, end: point(c, outer, CGFloat(i) * 60 + rotation + 40), options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        ctx.addPath(blade)
        ctx.setStrokeColor(color(0x0A0A0C))
        ctx.setLineWidth(4)
        ctx.strokePath()
    }

    // Glass seen through the opening.
    let hexagon = CGMutablePath()
    hexagon.addLines(between: vertices)
    hexagon.closeSubpath()
    ctx.saveGState()
    ctx.addPath(hexagon)
    ctx.clip()
    ctx.drawRadialGradient(gradient([(0x8FA4FF, 0), (0x4458D8, 0.45), (0x10142E, 1)]),
                           startCenter: CGPoint(x: c.x - 34, y: c.y + 40), startRadius: 0,
                           endCenter: c, endRadius: inner * 1.05, options: [.drawsAfterEndLocation])
    ctx.setFillColor(color(0xFFFFFF, 0.55))
    ctx.fillEllipse(in: CGRect(x: c.x - 62, y: c.y + 26, width: 46, height: 30))
    ctx.setFillColor(color(0xFFFFFF, 0.18))
    ctx.fillEllipse(in: CGRect(x: c.x + 24, y: c.y - 64, width: 26, height: 16))
    ctx.restoreGState()

    ctx.restoreGState()

    // Hairline edge.
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.10))
    ctx.setLineWidth(2)
    ctx.strokePath()
    return ctx.makeImage()!
}

func png(_ image: CGImage) -> Data {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create PNG encoder")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot encode PNG") }
    return data as Data
}

// (iconset file name, pixel size, ICNS chunk type)
let sizes: [(name: String, pixels: Int, type: String)] = [
    ("icon_16x16", 16, "icp4"), ("icon_16x16@2x", 32, "ic11"), ("icon_32x32", 32, "icp5"),
    ("icon_32x32@2x", 64, "ic12"), ("icon_128x128", 128, "ic07"), ("icon_128x128@2x", 256, "ic13"),
    ("icon_256x256", 256, "ic08"), ("icon_256x256@2x", 512, "ic14"), ("icon_512x512", 512, "ic09"),
    ("icon_512x512@2x", 1024, "ic10"),
]

func bigEndian(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }

var chunks = Data()
for size in sizes {
    let encoded = png(render(size.pixels))
    try encoded.write(to: output.appendingPathComponent("\(size.name).png"))
    chunks.append(size.type.data(using: .ascii)!)
    chunks.append(bigEndian(UInt32(encoded.count + 8)))
    chunks.append(encoded)
}
print("icon: wrote \(sizes.count) images to \(output.path)")

// Optionally assemble the .icns directly (same result as `iconutil -c icns`).
if CommandLine.arguments.count > 2 {
    var icns = "icns".data(using: .ascii)!
    icns.append(bigEndian(UInt32(chunks.count + 8)))
    icns.append(chunks)
    try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("icon: wrote \(CommandLine.arguments[2])")
}
