#!/usr/bin/env swift
//
// RenderAppIcon.swift — renders the Cling iOS app icon into the asset catalog.
//
// Cling's mark is a **glossy 3D disc** — a domed white-glass button on the
// luminous indigo field, with a push pin molded into its face: an engraved
// base under a vivid violet→indigo gradient and glossy sheen, so the field's
// colour pops luminously through the glyph. Same material, lighting and molded-
// legend treatment as Clink's keycap "C" and Aware's shield disc.
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

// Draw `pin.fill` (point size `box`, centred at `center`) flat-filled with
// `fill` straight onto the current context. Drawn as a tinted NSImage so the
// glyph keeps Core Graphics' native antialiasing — mirrors Aware's `drawSymbol`.
// Used for the engraved base whose drop-shadow halo reads the pin as inset.
func drawPin(box: CGFloat, center: CGPoint, fill: NSColor) {
    let cfg = NSImage.SymbolConfiguration(pointSize: box, weight: .semibold)
    guard let sym = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return }
    let s = sym.size
    let tinted = NSImage(size: s)
    tinted.lockFocus()
    fill.set()
    let r = NSRect(origin: .zero, size: s)
    sym.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(at: NSPoint(x: center.x - s.width / 2, y: center.y - s.height / 2),
                from: NSRect(origin: .zero, size: s), operation: .sourceOver, fraction: 1.0)
}

// Draw `pin.fill` filled with a luminous diagonal gradient (`fillStops`, first
// colour at the top) plus a glossy top sheen, so the glyph pops off the glass
// like a molded, back-lit legend (cf. Clink's indigo "C", Aware's teal shield).
// Fill and sheen are composited `.sourceAtop` inside an offscreen the shape of
// the glyph, so both stay clipped to the pin with no stray edges.
func drawPinGradient(box: CGFloat, center: CGPoint,
                     fillStops: [(NSColor, CGFloat)], sheenTopAlpha: CGFloat) {
    let cfg = NSImage.SymbolConfiguration(pointSize: box, weight: .semibold)
    guard let sym = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return }
    let s = sym.size
    let img = NSImage(size: s)
    img.lockFocus()
    let r = NSRect(origin: .zero, size: s)
    NSColor.black.set()
    sym.draw(in: r)                                   // establish the shape + alpha
    NSGraphicsContext.current?.compositingOperation = .sourceAtop
    NSGradient(colors: fillStops.map { $0.0 },
               atLocations: fillStops.map { $0.1 }, colorSpace: .sRGB)!
        .draw(in: r, angle: -90)                       // first stop at top, descending
    NSGradient(colors: [NSColor(white: 1, alpha: sheenTopAlpha), NSColor(white: 1, alpha: 0)],
               atLocations: [0, 0.5], colorSpace: .sRGB)!
        .draw(in: r, angle: -90)                       // glossy upper sheen, fades by mid
    img.unlockFocus()
    img.draw(at: NSPoint(x: center.x - s.width / 2, y: center.y - s.height / 2),
             from: r, operation: .sourceOver, fraction: 1.0)
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

    // ── Pin glyph, molded into the disc face. Tinted → flat mid-grey so iOS maps
    //    its tint cleanly; light/dark → an engraved drop-shadow base under a
    //    vivid indigo→violet diagonal gradient + glossy sheen, so the field's
    //    colour pops luminously through the mark (cf. Clink's "C", Aware's
    //    shield). ────────────────────────────────────────────────────────────
    let glyphBox = discR * 0.95
    if isTinted {
        // Flat mid-grey so iOS maps its single tint over it cleanly.
        drawPin(box: glyphBox, center: discC, fill: NSColor(white: 0.40, alpha: 1))
    } else {
        // Engraved drop-shadow so the pin reads as inset into the glass.
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -size * 0.004), blur: size * 0.012,
                     color: isDark ? rgb(0, 0, 0, 0.55) : rgb(0.10, 0.14, 0.30, 0.45))
        let base: NSColor = isDark ? NSColor(srgbRed: 0.05, green: 0.06, blue: 0.12, alpha: 1)
                                   : NSColor(srgbRed: 0.20, green: 0.26, blue: 0.52, alpha: 1)
        drawPin(box: glyphBox, center: discC, fill: base)
        cg.restoreGState()

        // Vivid saturated violet→indigo→deep-blue diagonal + glossy sheen.
        let fillStops: [(NSColor, CGFloat)] = isDark
            ? [(NSColor(srgbRed: 0.62, green: 0.50, blue: 1.00, alpha: 1), 0),    // bright violet
               (NSColor(srgbRed: 0.40, green: 0.40, blue: 0.95, alpha: 1), 0.5), // electric indigo
               (NSColor(srgbRed: 0.20, green: 0.26, blue: 0.70, alpha: 1), 1)]   // deep blue
            : [(NSColor(srgbRed: 0.50, green: 0.32, blue: 0.98, alpha: 1), 0),    // bright violet
               (NSColor(srgbRed: 0.28, green: 0.30, blue: 0.92, alpha: 1), 0.5), // electric indigo
               (NSColor(srgbRed: 0.12, green: 0.20, blue: 0.74, alpha: 1), 1)]   // deep blue
        drawPinGradient(box: glyphBox, center: discC,
                        fillStops: fillStops, sheenTopAlpha: isDark ? 0.18 : 0.30)
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
