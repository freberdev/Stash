#!/usr/bin/swift
// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [output.icns] [preview.png]

import AppKit
import CoreGraphics

/// Draws the icon on a 1024-point canvas with the origin in the lower left corner:
/// a tray with two sheets of paper standing in it.
func drawIcon(in ctx: CGContext) {
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    let space = CGColorSpaceCreateDeviceRGB()

    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }
    func gradient(_ top: CGColor, _ bottom: CGColor) -> CGGradient {
        CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    }

    // Soft shadow under the plate.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.28))
    ctx.addPath(platePath)
    ctx.setFillColor(color(0.20, 0.47, 0.86))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()

    // The plate, lighter at the top.
    ctx.drawLinearGradient(
        gradient(color(0.40, 0.74, 0.96), color(0.15, 0.40, 0.84)),
        start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])

    // A sheet of paper, turned around its centre, with a few lines of writing on it.
    func sheet(centre: CGPoint, degrees: CGFloat, paper: CGColor, ink: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.rotate(by: degrees * .pi / 180)
        let rect = CGRect(x: -170, y: -220, width: 340, height: 440)
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0.03, 0.12, 0.35, 0.35))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.setFillColor(paper)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(26)
        ctx.setLineCap(.round)
        for (y, endX) in [(CGFloat(130), CGFloat(90)), (CGFloat(60), CGFloat(110)), (CGFloat(-10), CGFloat(20))] {
            ctx.move(to: CGPoint(x: -110, y: y))
            ctx.addLine(to: CGPoint(x: endX, y: y))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
    sheet(centre: CGPoint(x: 590, y: 560), degrees: -9, paper: color(1.00, 0.86, 0.42), ink: color(0.60, 0.42, 0.05, 0.55))
    sheet(centre: CGPoint(x: 440, y: 540), degrees: 7, paper: color(1, 1, 1), ink: color(0.20, 0.38, 0.70, 0.45))

    // The front of the tray, which hides the lower part of the sheets.
    let tray = CGRect(x: 190, y: 190, width: 644, height: 290)
    let trayPath = CGPath(roundedRect: tray, cornerWidth: 70, cornerHeight: 70, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 26, color: color(0.03, 0.10, 0.30, 0.40))
    ctx.addPath(trayPath)
    ctx.setFillColor(color(0.10, 0.24, 0.58))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(trayPath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(color(0.16, 0.33, 0.72), color(0.07, 0.17, 0.46)),
        start: CGPoint(x: 0, y: tray.maxY), end: CGPoint(x: 0, y: tray.minY), options: [])
    ctx.restoreGState()

    // The grip on the front of the tray.
    let grip = CGRect(x: 432, y: 372, width: 160, height: 44)
    ctx.addPath(CGPath(roundedRect: grip, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.setFillColor(color(1, 1, 1, 0.82))
    ctx.fillPath()

    ctx.restoreGState()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "Resources/AppIcon.icns"
let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for (name, pixels) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    try png(pixels: pixels).write(to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("Wrote \(output)")

if arguments.count > 2 {
    try png(pixels: 512).write(to: URL(fileURLWithPath: arguments[2]))
    print("Wrote \(arguments[2])")
}
