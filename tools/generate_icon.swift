import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func render(pixels: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let scale = pixels / 1024
    NSColor(calibratedRed: 0.11, green: 0.42, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: pixels, height: pixels), xRadius: 220 * scale, yRadius: 220 * scale).fill()
    NSColor.white.setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 250 * scale, y: 190 * scale, width: 520 * scale, height: 640 * scale),
        xRadius: 72 * scale,
        yRadius: 72 * scale
    ).fill()
    NSColor(calibratedRed: 0.11, green: 0.42, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 300 * scale, y: 280 * scale, width: 420 * scale, height: 470 * scale),
        xRadius: 28 * scale,
        yRadius: 28 * scale
    ).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 470 * scale, y: 220 * scale, width: 84 * scale, height: 84 * scale)).fill()
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("png failed \(url.path)\n", stderr)
        exit(1)
    }
    try! png.write(to: url)
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]
for (name, pixels) in sizes {
    writePNG(render(pixels: pixels), to: URL(fileURLWithPath: output).appendingPathComponent(name))
}
