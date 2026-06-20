#!/usr/bin/env swift
//
// RenderAppIcon.swift — renders the Cling iOS app icon into the asset catalog.
//
// Cling's mark is a **glossy 3D disc** — a domed violet-glass button on the
// luminous indigo field, with a crisp white push pin embossed on its face.
// Same indigo family and lighting as Clink's keycap, a different body.
//
// iOS specifics, both required:
//   • the background is drawn full-bleed and fully opaque (no squircle clip,
//     no rim stroke) — iOS applies its own icon mask, and App Store icons must
//     not have an alpha channel.
//   • a single 1024px PNG (plus a 512px gallery copy) instead of an .iconset.
//
import AppKit

let size = 1024.0
let outDir = "Resources/Assets.xcassets/AppIcon.appiconset"
let galleryPath = "Resources/icon-512.png"

let arg = CommandLine.arguments.dropFirst().first ?? "all"
let modes = (arg == "all") ? ["light", "dark", "tinted"] : [arg]

func renderPNG(size: CGFloat, mode: String) -> Data? {
    let px = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(in: ctx.cgContext, size: size, mode: mode)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// Render `pin.fill` as a white-on-clear alpha mask of side `box`, centred at
// `center` on the canvas — used as a clip stencil to emboss the glyph.
func pinMask(canvas: CGFloat, box: CGFloat, center: CGPoint) -> CGImage? {
    let px = Int(canvas)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let g = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: box, weight: .semibold)
    guard let sym = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return nil }
    let s = sym.size
    let r = CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    NSColor.white.set()
    sym.draw(in: r)
    r.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage
}

func draw(in cg: CGContext, size: CGFloat, mode: String) {
    let isDark   = (mode == "dark")
    let isTinted = (mode == "tinted")
    let space = CGColorSpaceCreateDeviceRGB()
    func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }
    func grad(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map { $0.0 } as CFArray,
                   locations: stops.map { $0.1 })!
    }
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // ── The luminous indigo field — painted as the background, and again
    //    through the pin cutout so the glyph reveals the field (Clink's "C"). ──
    func drawField() {
        let bg = isDark
            ? grad([(rgb(0.16, 0.13, 0.32), 0), (rgb(0.08, 0.10, 0.26), 0.52), (rgb(0.02, 0.03, 0.10), 1)])
            : grad([(rgb(0.46, 0.36, 0.80), 0), (rgb(0.24, 0.30, 0.70), 0.52), (rgb(0.07, 0.09, 0.24), 1)])
        cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let bloomC = CGPoint(x: size * 0.5, y: size * 0.66)
        cg.drawRadialGradient(grad([(rgb(0.78, 0.86, 1.00, isDark ? 0.20 : 0.40), 0),
                                    (rgb(0.60, 0.70, 1.00, 0.00), 1)]),
                              startCenter: bloomC, startRadius: 0,
                              endCenter: bloomC, endRadius: size * 0.55, options: [])
        let warmC = CGPoint(x: size * 0.90, y: size * 0.12)
        cg.drawRadialGradient(grad([(rgb(0.80, 0.34, 0.74, isDark ? 0.20 : 0.32), 0),
                                    (rgb(0.80, 0.34, 0.74, 0.00), 1)]),
                              startCenter: warmC, startRadius: 0,
                              endCenter: warmC, endRadius: size * 0.5, options: [])
    }
    if !isTinted { drawField() }

    // ── 3D disc — an extruded violet-glass puck (visible side wall = depth) ────
    let discR = size * 0.365                         // vertical radius
    let discRX = discR * 1.07                        // a touch wider — the 3D wall reads tall
    let depth = size * 0.060                         // extrusion height (the wall)
    let discC = CGPoint(x: size * 0.5, y: size * 0.5 + depth * 0.55 + size * 0.005)
    let topRect = CGRect(x: discC.x - discRX, y: discC.y - discR, width: discRX * 2, height: discR * 2)
    func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    // Contact shadow grounding the puck on the field (skip tinted).
    if !isTinted {
        cg.saveGState()
        cg.translateBy(x: 0, y: -depth)
        cg.setShadow(offset: CGSize(width: 0, height: -size * 0.022), blur: size * 0.06,
                     color: rgb(0.01, 0.02, 0.06, 0.55))
        cg.setFillColor(rgb(0, 0, 0, 1))
        cg.fillEllipse(in: topRect)
        cg.restoreGState()
    }

    // Extruded side wall: fill the disc at descending offsets, darkening to the
    // base, so the puck reads as a solid object with thickness.
    let steps = Int(depth)
    for i in stride(from: steps, through: 0, by: -1) {
        let t = Double(i) / Double(steps)            // 1 at base, 0 at top edge
        let r, g, b: Double
        if isTinted {
            r = lerp(0.62, 0.30, t); g = lerp(0.62, 0.30, t); b = lerp(0.62, 0.30, t)
        } else if isDark {
            r = lerp(0.26, 0.08, t); g = lerp(0.28, 0.09, t); b = lerp(0.34, 0.13, t)
        } else {
            r = lerp(0.74, 0.40, t); g = lerp(0.76, 0.42, t); b = lerp(0.82, 0.52, t)
        }
        cg.saveGState()
        cg.translateBy(x: 0, y: -CGFloat(i))
        cg.setFillColor(rgb(r, g, b, 1))
        cg.fillEllipse(in: topRect)
        cg.restoreGState()
    }

    // Top face: white glass, exactly Clink's keycap material — a soft vertical
    // gradient, a dished edge, and a broad upper sheen. No radial highlight (a
    // radial reads as a stray little circle on the face).
    cg.saveGState()
    cg.addEllipse(in: topRect); cg.clip()
    let face: CGGradient
    if isTinted {
        face = grad([(rgb(0.98, 0.98, 0.98), 0), (rgb(0.90, 0.90, 0.90), 0.55), (rgb(0.80, 0.80, 0.80), 1)])
    } else if isDark {
        face = grad([(rgb(0.30, 0.32, 0.40), 0), (rgb(0.22, 0.24, 0.32), 0.55), (rgb(0.15, 0.17, 0.24), 1)])
    } else {
        face = grad([(rgb(0.99, 1.00, 1.00), 0), (rgb(0.93, 0.95, 0.99), 0.55), (rgb(0.84, 0.88, 0.96), 1)])
    }
    cg.drawLinearGradient(face, start: CGPoint(x: discC.x, y: topRect.maxY),
                          end: CGPoint(x: discC.x, y: topRect.minY), options: [])
    // Dished edge: darken toward the rim so the centre reads gently scooped.
    let dish: CGGradient
    if isTinted {
        dish = grad([(rgb(0.55, 0.55, 0.55, 0.0), 0), (rgb(0.55, 0.55, 0.55, 0.0), 0.6), (rgb(0.45, 0.45, 0.45, 0.35), 1)])
    } else if isDark {
        dish = grad([(rgb(0.10, 0.11, 0.16, 0.0), 0), (rgb(0.10, 0.11, 0.16, 0.0), 0.6), (rgb(0.06, 0.07, 0.11, 0.5), 1)])
    } else {
        dish = grad([(rgb(0.80, 0.85, 0.94, 0.0), 0), (rgb(0.80, 0.85, 0.94, 0.0), 0.6), (rgb(0.62, 0.68, 0.82, 0.45), 1)])
    }
    cg.drawRadialGradient(dish, startCenter: discC, startRadius: 0,
                          endCenter: discC, endRadius: discRX, options: [])
    // Broad soft sheen across the upper face.
    cg.saveGState()
    cg.translateBy(x: discC.x, y: discC.y + discR * 0.34); cg.scaleBy(x: 1.0, y: 0.5)
    cg.drawRadialGradient(grad([(rgb(1, 1, 1, isDark ? 0.32 : 0.7), 0), (rgb(1, 1, 1, 0.0), 1)]),
                          startCenter: .zero, startRadius: 0, endCenter: .zero,
                          endRadius: discR * 0.66, options: [])
    cg.restoreGState()
    cg.restoreGState()

    // Crisp lit rim along the top edge of the top face.
    cg.saveGState()
    cg.addEllipse(in: topRect.insetBy(dx: size * 0.004, dy: size * 0.004))
    cg.setLineWidth(size * 0.012)
    cg.replacePathWithStrokedPath(); cg.clip()
    cg.drawLinearGradient(grad([(rgb(1, 1, 1, 0.95), 0), (rgb(1, 1, 1, 0.0), 1)]),
                          start: CGPoint(x: discC.x, y: topRect.maxY),
                          end: CGPoint(x: discC.x, y: discC.y), options: [])
    cg.restoreGState()

    // ── Pin glyph, knocked out of the disc — the field shows through it, the
    //    way Clink's "C" reveals the gradient behind the keycap. ───────────────
    let glyphBox = discR * 0.95
    guard let pin = pinMask(canvas: size, box: glyphBox, center: discC) else { return }
    func clipPin(dy: CGFloat = 0) {
        // dy > 0 shifts the glyph up; dy < 0 shifts it down.
        cg.clip(to: CGRect(x: 0, y: dy, width: size, height: size), mask: pin)
    }

    if isDark || isTinted {
        // The dark/tinted fields are near-black, so a cutout would vanish — fill
        // the glyph instead, like Clink's dark "C": cool-white on the graphite
        // face, mid-grey when tinted (so iOS can tint it).
        let fill = isDark
            ? grad([(rgb(0.98, 0.99, 1.00), 0), (rgb(0.82, 0.86, 0.96), 1)])
            : grad([(rgb(0.46, 0.46, 0.46), 0), (rgb(0.34, 0.34, 0.34), 1)])
        cg.saveGState()
        clipPin()
        cg.drawLinearGradient(fill,
                              start: CGPoint(x: 0, y: discC.y + glyphBox * 0.5),
                              end: CGPoint(x: 0, y: discC.y - glyphBox * 0.5),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    } else {
        // Light mode: cutout — re-paint the bright field through the pin shape.
        cg.saveGState()
        clipPin()
        drawField()
        cg.restoreGState()
    }
}

let fileFor = ["light": "icon-1024.png", "dark": "icon-1024-dark.png", "tinted": "icon-1024-tinted.png"]
for mode in modes {
    guard let name = fileFor[mode] else { fatalError("unknown mode: \(mode)") }
    guard let png = renderPNG(size: size, mode: mode) else { fatalError("render failed: \(mode)") }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("→ \(outDir)/\(name)")
    if mode == "light", let png512 = renderPNG(size: 512, mode: "light") {
        try! png512.write(to: URL(fileURLWithPath: galleryPath))
        print("→ \(galleryPath)")
    }
}
