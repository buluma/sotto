import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
func png(_ size: Int, background: Bool, white: Bool = true) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    if background {
        NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 224, yRadius: 224).fill()
    }
    (white ? NSColor.white : NSColor.black).setStroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 716, y: 700))
    path.curve(to: NSPoint(x: 310, y: 660), controlPoint1: NSPoint(x: 600, y: 835), controlPoint2: NSPoint(x: 295, y: 808))
    path.curve(to: NSPoint(x: 512, y: 512), controlPoint1: NSPoint(x: 305, y: 563), controlPoint2: NSPoint(x: 425, y: 544))
    path.curve(to: NSPoint(x: 714, y: 364), controlPoint1: NSPoint(x: 615, y: 474), controlPoint2: NSPoint(x: 719, y: 463))
    path.curve(to: NSPoint(x: 308, y: 324), controlPoint1: NSPoint(x: 729, y: 216), controlPoint2: NSPoint(x: 424, y: 189))
    path.lineWidth = 76; path.lineCapStyle = .round; path.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let fm = FileManager.default
let assets = root.appendingPathComponent("Assets")
try png(1024, background: true).write(to: assets.appendingPathComponent("AppIcon-1024x1024.png"))
let iconset = URL(fileURLWithPath: "/tmp/Sotto.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    try png(size, background: true).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size*2, background: true).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
for folder in ["Assets", "Sources/Sotto/Resources"] {
    let dir = root.appendingPathComponent(folder)
    try png(18, background: false, white: false).write(to: dir.appendingPathComponent("menubar-icon.png"))
    try png(36, background: false, white: false).write(to: dir.appendingPathComponent("menubar-icon@2x.png"))
}
try png(512, background: false).write(to: root.appendingPathComponent("Sources/Sotto/Resources/sotto-mark.png"))
