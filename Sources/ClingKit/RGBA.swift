/**
 `RGBA`: a `Codable`, `Sendable` color value used throughout `PinAppearance`.
 Bridges to SwiftUI `Color` and UIKit `UIColor` without importing either in the
 model layer. Ported from ClinkKit so the two apps share one color idiom.
 */
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Codable, value-type color so a pin's appearance can round-trip through the
/// App Group as JSON. SwiftUI's `Color` is not reliably Codable across OS
/// versions, so we store raw sRGB components and bridge to `Color` on demand.
public struct RGBA: Codable, Equatable, Sendable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `RGBA(hex: 0x6D3FB8)` — convenient for design tokens.
    public init(hex: UInt32, a: Double = 1) {
        self.r = Double((hex >> 16) & 0xFF) / 255.0
        self.g = Double((hex >> 8) & 0xFF) / 255.0
        self.b = Double(hex & 0xFF) / 255.0
        self.a = a
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    #if canImport(UIKit)
    /// Build from a SwiftUI `Color` (resolved through UIKit) — used by the
    /// appearance editor's `ColorPicker` to capture a chosen colour.
    public init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }

    public var uiColor: UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }
    #endif
}
