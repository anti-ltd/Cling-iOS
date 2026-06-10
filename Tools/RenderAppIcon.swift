#!/usr/bin/env swift
//
// RenderAppIcon.swift — renders the Cling iOS app icon into the asset catalog.
//
// Run via `make icon`. Brand: a liquid-glass disc holding a pin glyph, floating
// on a deep indigo→violet gradient — the same glass-on-indigo family look as
// Clink's keycap icon.
//
import AppKit

let size = 1024.0
let outDir = "Resources/Assets.xcassets/AppIcon.appiconset"
let outPath = "\(outDir)/icon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

let rgb = CGColorSpaceCreateDeviceRGB()

// Full-bleed diagonal gradient, deep indigo (top-left) → violet (bottom-right).
let bg = CGGradient(
    colorsSpace: rgb,
    colors: [
        NSColor(srgbRed: 0x1A / 255.0, green: 0x16 / 255.0, blue: 0x3F / 255.0, alpha: 1).cgColor,
        NSColor(srgbRed: 0x3B / 255.0, green: 0x2E / 255.0, blue: 0x83 / 255.0, alpha: 1).cgColor,
        NSColor(srgbRed: 0x6D / 255.0, green: 0x3F / 255.0, blue: 0xB8 / 255.0, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(
    bg,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: [])

// Soft radial glow behind the glass disc so it reads as lit from within.
let glow = CGGradient(
    colorsSpace: rgb,
    colors: [
        NSColor(srgbRed: 0.75, green: 0.65, blue: 1.0, alpha: 0.55).cgColor,
        NSColor(srgbRed: 0.75, green: 0.65, blue: 1.0, alpha: 0.0).cgColor,
    ] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: size * 0.5, y: size * 0.54), startRadius: 0,
    endCenter: CGPoint(x: size * 0.5, y: size * 0.54), endRadius: size * 0.46,
    options: [])

// Frosted glass disc: translucent white fill, lit top rim, faint outline,
// specular sheen arc — the hand-built liquid-glass recipe at icon scale.
let discRadius = size * 0.305
let discCenter = CGPoint(x: size * 0.5, y: size * 0.52)
let discRect = CGRect(
    x: discCenter.x - discRadius, y: discCenter.y - discRadius,
    width: discRadius * 2, height: discRadius * 2)

// Drop shadow under the disc (floats above the gradient).
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -size * 0.018),
    blur: size * 0.05,
    color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
ctx.fillEllipse(in: discRect)
ctx.restoreGState()

// Frosting: vertical white wash, stronger at the top.
ctx.saveGState()
ctx.addEllipse(in: discRect)
ctx.clip()
let frost = CGGradient(
    colorsSpace: rgb,
    colors: [
        NSColor.white.withAlphaComponent(0.30).cgColor,
        NSColor.white.withAlphaComponent(0.08).cgColor,
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(
    frost,
    start: CGPoint(x: discCenter.x, y: discRect.maxY),
    end: CGPoint(x: discCenter.x, y: discRect.minY),
    options: [])
// Specular sheen: bright crescent hugging the upper-left of the disc.
let sheen = CGGradient(
    colorsSpace: rgb,
    colors: [
        NSColor.white.withAlphaComponent(0.45).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
    ] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(
    sheen,
    startCenter: CGPoint(x: discCenter.x - discRadius * 0.45, y: discCenter.y + discRadius * 0.55),
    startRadius: 0,
    endCenter: CGPoint(x: discCenter.x - discRadius * 0.45, y: discCenter.y + discRadius * 0.55),
    endRadius: discRadius * 0.9,
    options: [])
ctx.restoreGState()

// Lit rim: bright on top, fading out toward the bottom.
ctx.saveGState()
ctx.addEllipse(in: discRect.insetBy(dx: size * 0.004, dy: size * 0.004))
ctx.replacePathWithStrokedPath()
ctx.clip()
let rim = CGGradient(
    colorsSpace: rgb,
    colors: [
        NSColor.white.withAlphaComponent(0.85).cgColor,
        NSColor.white.withAlphaComponent(0.10).cgColor,
    ] as CFArray,
    locations: [0, 1])!
ctx.setLineWidth(size * 0.008)
ctx.drawLinearGradient(
    rim,
    start: CGPoint(x: discCenter.x, y: discRect.maxY),
    end: CGPoint(x: discCenter.x, y: discRect.minY),
    options: [])
ctx.restoreGState()

// Centred white pin glyph, slightly oversized inside the disc.
let glyphPt = size * 0.34
let config = NSImage.SymbolConfiguration(pointSize: glyphPt, weight: .medium)
if let symbol = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let gs = tinted.size
    let origin = NSPoint(
        x: discCenter.x - gs.width / 2,
        y: discCenter.y - gs.height / 2)
    tinted.draw(
        at: origin, from: NSRect(origin: .zero, size: gs),
        operation: .sourceOver, fraction: 0.96)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("→ \(outPath)")
