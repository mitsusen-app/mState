// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the repo root; needs iconutil)
import AppKit

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024

    // macOS icon grid: an 824pt rounded square centered in the 1024pt canvas.
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1).setFill()
    NSBezierPath(roundedRect: plate, xRadius: 185 * s, yRadius: 185 * s).fill()

    // Five load bars, one lit: the same language as the panel's CORES card.
    let heights: [CGFloat] = [190, 330, 250, 470, 360]
    for (i, height) in heights.enumerated() {
        let bar = NSRect(x: (234 + CGFloat(i) * 118) * s, y: 280 * s, width: 84 * s, height: height * s)
        (i == 3 ? NSColor(calibratedRed: 1, green: 0.62, blue: 0.16, alpha: 1)
                : NSColor(calibratedWhite: 0.86, alpha: 1)).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 20 * s, yRadius: 20 * s).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mState.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try render(pixels: size * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
exit(iconutil.terminationStatus)
