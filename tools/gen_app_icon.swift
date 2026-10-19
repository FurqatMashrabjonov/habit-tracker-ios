// Draws the app icon and the launch image from the same tiles as Android's adaptive icon
// (ic_launcher_foreground.xml): four 38 dp tiles stepping 4 dp to the right, tilted −12°, the front
// one on the centre line with the check. Run: swift tools/gen_app_icon.swift
//
// Outputs, in HabitDots/Assets.xcassets:
//   AppIcon.appiconset   light (Paper), dark (Night) and tinted (greyscale) 1024 px, iOS 18 picks one
//                        from the home screen's appearance.
//   LaunchIcon.imageset  transparent 240 px, light and dark, over LaunchBackground.
import AppKit

struct Look {
    var ground: NSColor?          // nil = transparent
    var back: [NSColor]           // the three tiles behind, back to front
    var front: NSColor
    var check: NSColor
}

func c(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let paper = Look(ground: c(0xFFFFFF), back: [c(0xD3D3D1), c(0xA5A4A0), c(0x6E6C67)], front: c(0x37352F), check: c(0xFFFFFF))
let night = Look(ground: c(0x1F1E1B), back: [c(0x3A3936), c(0x5C5A55), c(0x9A9892)], front: c(0xF2F1EE), check: c(0x1F1E1B))
// Tinted: a greyscale picture on black; the system maps brightness to the user's tint.
let tinted = Look(ground: c(0x000000), back: [c(0x3C3C3C), c(0x6A6A6A), c(0xA0A0A0)], front: c(0xFFFFFF), check: c(0x000000))

/// One tile, centred on the origin, in dp: a 38 dp squircle.
func tilePath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -19, y: 0))
    p.addCurve(to: CGPoint(x: 0, y: -19), control1: CGPoint(x: -19, y: -15.96), control2: CGPoint(x: -15.96, y: -19))
    p.addCurve(to: CGPoint(x: 19, y: 0), control1: CGPoint(x: 15.96, y: -19), control2: CGPoint(x: 19, y: -15.96))
    p.addCurve(to: CGPoint(x: 0, y: 19), control1: CGPoint(x: 19, y: 15.96), control2: CGPoint(x: 15.96, y: 19))
    p.addCurve(to: CGPoint(x: -19, y: 0), control1: CGPoint(x: -15.96, y: 19), control2: CGPoint(x: -19, y: 15.96))
    p.closeSubpath()
    return p
}

/// `units`: how many dp of the 108 dp canvas the square image spans, centred on (54, 54).
func render(_ look: Look, size: Int, units: CGFloat, shift: CGFloat = 0, to url: URL) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha: CGImageAlphaInfo = look.ground == nil ? .premultipliedLast : .noneSkipLast
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: alpha.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    if let g = look.ground { ctx.setFillColor(g.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }
    // dp coordinates with y down, like the Android vector.
    let s = CGFloat(size) / units
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: shift, y: 0)
    ctx.rotate(by: -12 * .pi / 180)
    let tile = tilePath()
    for (i, x) in [42.0, 46, 50].enumerated() {
        ctx.saveGState(); ctx.translateBy(x: CGFloat(x) - 54, y: 0)
        ctx.addPath(tile); ctx.setFillColor(look.back[i].cgColor); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.addPath(tile); ctx.setFillColor(look.front.cgColor); ctx.fillPath()
    let check = CGMutablePath()
    check.move(to: CGPoint(x: -9.77, y: 0.57)); check.addLine(to: CGPoint(x: -2.88, y: 7.47)); check.addLine(to: CGPoint(x: 9.77, y: -7.47))
    ctx.addPath(check)
    ctx.setStrokeColor(look.check.cgColor); ctx.setLineWidth(5.17); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.strokePath()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let assets = URL(fileURLWithPath: "HabitDots/Assets.xcassets")
let icon = assets.appendingPathComponent("AppIcon.appiconset")
// 62 dp across, nudged 4.5 dp right: the stack fills the icon with even margins. iOS has no round
// mask, so the stack's outline is balanced in the square instead of putting the front tile dead centre.
let span: CGFloat = 62, nudge: CGFloat = 4.5
render(paper, size: 1024, units: span, shift: nudge, to: icon.appendingPathComponent("icon-1024.png"))
render(night, size: 1024, units: span, shift: nudge, to: icon.appendingPathComponent("icon-1024-dark.png"))
render(tinted, size: 1024, units: span, shift: nudge, to: icon.appendingPathComponent("icon-1024-tinted.png"))
try! """
{
  "images" : [
    { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "icon-1024-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "icon-1024-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: icon.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let launch = assets.appendingPathComponent("LaunchIcon.imageset")
var clearPaper = paper; clearPaper.ground = nil
var clearNight = night; clearNight.ground = nil
render(clearPaper, size: 240, units: span, shift: nudge, to: launch.appendingPathComponent("launch.png"))
render(clearNight, size: 240, units: span, shift: nudge, to: launch.appendingPathComponent("launch-dark.png"))
try! """
{
  "images" : [
    { "filename" : "launch.png", "idiom" : "universal", "scale" : "3x" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "launch-dark.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: launch.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("app icon and launch image written")
