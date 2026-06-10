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
        showsExpiry: Bool = true
    ) {
        self.accent = accent
        self.accentEnd = accentEnd
        self.symbolName = symbolName
        self.density = density
        self.style = style
        self.fontDesign = fontDesign
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
        case accent, accentEnd, symbolName, density, style, fontDesign, showsExpiry
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = (try? c.decode(RGBA.self, forKey: .accent)) ?? PinAppearance.indigo
        accentEnd = try? c.decode(RGBA.self, forKey: .accentEnd)
        symbolName = (try? c.decode(String.self, forKey: .symbolName)) ?? "pin.fill"
        density = (try? c.decode(LayoutDensity.self, forKey: .density)) ?? .regular
        style = (try? c.decode(PinStyle.self, forKey: .style)) ?? .glass
        fontDesign = (try? c.decode(PinFontDesign.self, forKey: .fontDesign)) ?? .standard
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
