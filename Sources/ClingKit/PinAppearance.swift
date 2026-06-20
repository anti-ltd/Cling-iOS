/**
 How a pin looks — accent colour, glyph, layout density, surface style. Lives
 in the Live Activity's `ContentState` (not its attributes) deliberately, so
 editing appearance updates a live pin without restarting the activity.
 */
import SwiftUI

/// How much a pin's views breathe.
public enum LayoutDensity: String, Codable, Sendable, Hashable, CaseIterable {
    /// Tight — more pins per glance.
    case compact
    /// Comfortable — the default.
    case regular
}

/// The surface treatment of a pin's lock-screen card.
public enum PinStyle: String, Codable, Sendable, Hashable, CaseIterable {
    /// Liquid glass — the family signature.
    case glass
    /// Solid accent-tinted card.
    case solid
    /// Quiet outline, content forward.
    case outline
}

/// Typeface personality for the pin's text — the same lever Clink's themes
/// pull (a serif note reads like paper; mono suits a 2FA code).
public enum PinFontDesign: String, Codable, Sendable, Hashable, CaseIterable {
    case standard, rounded, serif, mono

    public var design: Font.Design {
        switch self {
        case .standard: .default
        case .rounded:  .rounded
        case .serif:    .serif
        case .mono:     .monospaced
        }
    }
}

/// The edge a pin's card draws. The Dynamic Island's compact/expanded regions
/// are system-framed (we only colour their keyline), so a border lands on the
/// lock-screen card and the in-app stage — a quiet way to firm up `outline`
/// and `glass` surfaces.
public enum PinBorder: String, Codable, Sendable, Hashable, CaseIterable {
    /// No stroke — the surface stands on its own.
    case none
    /// A faint neutral hairline, independent of accent.
    case hairline
    /// A confident stroke in the pin's accent.
    case accent

    /// The stroke colour for a card with the given accent, or nil for `.none`.
    public func strokeColor(accent: Color) -> Color? {
        switch self {
        case .none:     nil
        case .hairline: .white.opacity(0.22)
        case .accent:   accent.opacity(0.85)
        }
    }

    public var lineWidth: CGFloat {
        switch self {
        case .none:     0
        case .hairline: 1
        case .accent:   1.5
        }
    }
}

public struct PinAppearance: Codable, Hashable, Sendable {
    public var accent: RGBA
    /// When set, the accent renders as a two-stop gradient (accent → accentEnd)
    /// on the glyph and surfaces. Single-color contexts (activity background
    /// tint, text) use `accent`.
    public var accentEnd: RGBA?
    /// SF Symbol shown wherever the pin needs a glyph (compact island, rows).
    public var symbolName: String
    public var density: LayoutDensity
    public var style: PinStyle
    public var fontDesign: PinFontDesign
    /// The card edge. Like density/style/fontDesign, this is part of the
    /// global "feel" (`GlobalPinStyle`) — stored here because it travels in
    /// the ContentState the widget renders from.
    public var border: PinBorder
    /// The "Pinned until HH:mm" caption on the lock-screen card. On by
    /// default (expiry honesty), but the pin is the user's — hideable. The
    /// stale notice ("no longer pinned") always shows; that one's actionable.
    public var showsExpiry: Bool

    public init(
        accent: RGBA,
        accentEnd: RGBA? = nil,
        symbolName: String,
        density: LayoutDensity = .regular,
        style: PinStyle = .glass,
        fontDesign: PinFontDesign = .standard,
        border: PinBorder = .none,
        showsExpiry: Bool = true
    ) {
        self.accent = accent
        self.accentEnd = accentEnd
        self.symbolName = symbolName
        self.density = density
        self.style = style
        self.fontDesign = fontDesign
        self.border = border
        self.showsExpiry = showsExpiry
    }

    /// The accent as a SwiftUI gradient — collapses to a flat color when no
    /// end stop is set, so callers can use this unconditionally for fills.
    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent.color, (accentEnd ?? accent).color],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Forward-compatible decoding
    //
    // Stored pins predate accentEnd/fontDesign; decode field-by-field with
    // fallbacks so old JSON (and future additions) never invalidate the store.

    private enum CodingKeys: String, CodingKey {
        case accent, accentEnd, symbolName, density, style, fontDesign, border, showsExpiry
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = (try? c.decode(RGBA.self, forKey: .accent)) ?? PinAppearance.indigo
        accentEnd = try? c.decode(RGBA.self, forKey: .accentEnd)
        symbolName = (try? c.decode(String.self, forKey: .symbolName)) ?? "pin.fill"
        density = (try? c.decode(LayoutDensity.self, forKey: .density)) ?? .regular
        style = (try? c.decode(PinStyle.self, forKey: .style)) ?? .glass
        fontDesign = (try? c.decode(PinFontDesign.self, forKey: .fontDesign)) ?? .standard
        border = (try? c.decode(PinBorder.self, forKey: .border)) ?? .none
        showsExpiry = (try? c.decode(Bool.self, forKey: .showsExpiry)) ?? true
    }

    // MARK: Family palette
    //
    // Echoes Clink's liquid theme accents so the two apps read as siblings.

    public static let indigo = RGBA(hex: 0x6D5AE6)
    public static let mint = RGBA(hex: 0x30D2A5)
    public static let ember = RGBA(hex: 0xFF7A4D)
    public static let sky = RGBA(hex: 0x4DA8FF)
    public static let rose = RGBA(hex: 0xFF5E8A)
    public static let gold = RGBA(hex: 0xFFC34D)

    /// The accent swatches offered in the appearance editor.
    public static let accentPresets: [RGBA] = [indigo, mint, ember, sky, rose, gold]
}

/// The app-wide *feel* every pin and the Dynamic Island share: surface, type,
/// density and border. Accent and glyph stay per-type (each pin type keeps its
/// colour-coding and icon) — this is the chrome that unifies them. Edited once
/// in Settings, then applied onto each pin's per-type base to produce the
/// `PinAppearance` that actually renders, so changing it re-dresses every live
/// pin at once.
public struct GlobalPinStyle: Codable, Hashable, Sendable {
    public var density: LayoutDensity
    public var style: PinStyle
    public var fontDesign: PinFontDesign
    public var border: PinBorder

    public init(
        density: LayoutDensity = .regular,
        style: PinStyle = .glass,
        fontDesign: PinFontDesign = .standard,
        border: PinBorder = .none
    ) {
        self.density = density
        self.style = style
        self.fontDesign = fontDesign
        self.border = border
    }

    public static let `default` = GlobalPinStyle()

    /// Overlay this house style onto a per-type base (accent + glyph),
    /// producing the appearance a pin renders with. Accent, accentEnd,
    /// symbol and showsExpiry are left untouched.
    public func apply(to base: PinAppearance) -> PinAppearance {
        var a = base
        a.density = density
        a.style = style
        a.fontDesign = fontDesign
        a.border = border
        return a
    }

    // MARK: Forward-compatible decoding — same discipline as the rest of the store.

    private enum CodingKeys: String, CodingKey { case density, style, fontDesign, border }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        density = (try? c.decode(LayoutDensity.self, forKey: .density)) ?? .regular
        style = (try? c.decode(PinStyle.self, forKey: .style)) ?? .glass
        fontDesign = (try? c.decode(PinFontDesign.self, forKey: .fontDesign)) ?? .standard
        border = (try? c.decode(PinBorder.self, forKey: .border)) ?? .none
    }
}
