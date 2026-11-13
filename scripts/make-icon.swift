import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        let bounds = NSRect(x: 70, y: 70, width: 884, height: 884)
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 195, yRadius: 195)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.22); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
        NSGradient(starting: NSColor(calibratedRed: 0.34, green: 0.50, blue: 0.98, alpha: 1), ending: NSColor(calibratedRed: 0.17, green: 0.25, blue: 0.64, alpha: 1))!.draw(in: shape, angle: -80)
        NSShadow().set()
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: NSRect(x: 230, y: 220, width: 564, height: 590), xRadius: 62, yRadius: 62).fill()
        NSColor(calibratedRed: 0.18, green: 0.31, blue: 0.76, alpha: 1).setFill()
        for x in [350, 650] { NSBezierPath(roundedRect: NSRect(x: x, y: 745, width: 28, height: 110), xRadius: 14, yRadius: 14).fill() }
        NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.98, alpha: 1).setFill()
        NSRect(x: 230, y: 652, width: 564, height: 5).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let text = NSAttributedString(string: "DDL", attributes: [.font: NSFont.systemFont(ofSize: 157, weight: .heavy), .foregroundColor: NSColor(calibratedRed: 0.22, green: 0.35, blue: 0.79, alpha: 1), .paragraphStyle: paragraph])
        text.draw(in: NSRect(x: 230, y: 350, width: 564, height: 225))
        NSColor(calibratedRed: 1, green: 0.75, blue: 0.25, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 640, y: 160, width: 205, height: 205)).fill()
        let clock = NSBezierPath(); clock.move(to: NSPoint(x: 743, y: 315)); clock.line(to: NSPoint(x: 743, y: 263)); clock.line(to: NSPoint(x: 780, y: 241)); clock.lineWidth = 17; clock.lineCapStyle = .round
        NSColor(calibratedRed: 0.27, green: 0.22, blue: 0.18, alpha: 1).setStroke(); clock.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
