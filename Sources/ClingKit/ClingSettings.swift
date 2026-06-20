/**
 App-wide preferences, persisted via `ClingStore` so future extensions read the
 same defaults. Decoding is field-by-field with fallbacks so adding a setting
 never invalidates an existing settings file.
 */
import Foundation

/// Which maps app handles "Walk me there" from a parking pin. Each builds a
/// walking-directions URL that needs no Info.plist query-scheme allowlist:
/// Apple's own `maps://`, and Google's universal https link (opens the Google
/// Maps app if installed, else Safari).
public enum MapProvider: String, Codable, CaseIterable, Sendable {
    case apple, google

    public var displayName: String {
        switch self {
        case .apple:  "Apple Maps"
        case .google: "Google Maps"
        }
    }

    /// Walking directions to a coordinate.
    public func walkingDirectionsURL(latitude: Double, longitude: Double) -> URL {
        switch self {
        case .apple:
            URL(string: "maps://?daddr=\(latitude),\(longitude)&dirflg=w")!
        case .google:
            URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(latitude),\(longitude)&travelmode=walking")!
        }
    }
}

public struct ClingSettings: Codable, Equatable, Sendable {
    /// The default appearance a new pin of each type starts from. Users tune
    /// these once and every future pin inherits the look. Only the accent and
    /// glyph fields matter here — the surface/type/density/border fields are
    /// overridden by `globalStyle` when a pin renders.
    public var defaultAppearances: [PinTypeID: PinAppearance]
    /// The house style every pin and the Dynamic Island wear — surface, type,
    /// density, border. Layered onto each pin's per-type accent + glyph.
    public var globalStyle: GlobalPinStyle
    /// Schedule "expires soon — keep it alive?" local notifications.
    public var renewalRemindersEnabled: Bool
    /// The duration chips offered in the timer quick-add.
    public var timerPresets: [TimeInterval]
    /// Accent for the app's own chrome (backdrop glow, card tint).
    public var appAccent: RGBA
    /// User-saved builder presets, shown after the built-in four.
    public var customPresets: [PinPreset]
    /// Which maps app a parking pin's "Walk me there" opens.
    public var mapProvider: MapProvider

    public static let `default` = ClingSettings(
        defaultAppearances: [
            .note: PinAppearance(accent: PinAppearance.indigo, symbolName: "note.text"),
            .timer: PinAppearance(accent: PinAppearance.ember, symbolName: "timer"),
            .parking: PinAppearance(accent: PinAppearance.sky, symbolName: "car.fill"),
            .decor: PinAppearance(accent: PinAppearance.rose, symbolName: "sparkles"),
        ],
        globalStyle: .default,
        renewalRemindersEnabled: true,
        timerPresets: [5 * 60, 15 * 60, 25 * 60, 60 * 60],
        appAccent: PinAppearance.indigo
    )

    public init(
        defaultAppearances: [PinTypeID: PinAppearance],
        globalStyle: GlobalPinStyle = .default,
        renewalRemindersEnabled: Bool,
        timerPresets: [TimeInterval],
        appAccent: RGBA,
        customPresets: [PinPreset] = [],
        mapProvider: MapProvider = .apple
    ) {
        self.defaultAppearances = defaultAppearances
        self.globalStyle = globalStyle
        self.renewalRemindersEnabled = renewalRemindersEnabled
        self.timerPresets = timerPresets
        self.appAccent = appAccent
        self.customPresets = customPresets
        self.mapProvider = mapProvider
    }

    /// The appearance a pin of the given base renders with: its per-type
    /// accent + glyph, dressed in the global house style.
    public func styled(_ base: PinAppearance) -> PinAppearance {
        globalStyle.apply(to: base)
    }

    /// The default appearance for a type, falling back to the shipped default
    /// if the stored file predates the type.
    public func defaultAppearance(for typeID: PinTypeID) -> PinAppearance {
        defaultAppearances[typeID]
            ?? Self.default.defaultAppearances[typeID]
            ?? PinAppearance(accent: PinAppearance.indigo, symbolName: "pin.fill")
    }

    // MARK: Forward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case defaultAppearances, globalStyle, renewalRemindersEnabled, timerPresets, appAccent, customPresets, mapProvider
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        defaultAppearances = (try? c.decode([PinTypeID: PinAppearance].self, forKey: .defaultAppearances)) ?? d.defaultAppearances
        globalStyle = (try? c.decode(GlobalPinStyle.self, forKey: .globalStyle)) ?? d.globalStyle
        renewalRemindersEnabled = (try? c.decode(Bool.self, forKey: .renewalRemindersEnabled)) ?? d.renewalRemindersEnabled
        timerPresets = (try? c.decode([TimeInterval].self, forKey: .timerPresets)) ?? d.timerPresets
        appAccent = (try? c.decode(RGBA.self, forKey: .appAccent)) ?? d.appAccent
        customPresets = (try? c.decode([PinPreset].self, forKey: .customPresets)) ?? []
        mapProvider = (try? c.decode(MapProvider.self, forKey: .mapProvider)) ?? d.mapProvider
    }

    /// The builder's preset row: one built-in per type (wearing the user's
    /// per-type default look), then the user's saved customs.
    @MainActor
    public func builderPresets() -> [PinPreset] {
        let builtIn = PinTypeID.allCases.map { typeID in
            PinPreset(
                // Stable ids so selection highlights survive re-renders.
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(PinTypeID.allCases.firstIndex(of: typeID) ?? 0)") ?? UUID(),
                name: PinRegistry.module(for: typeID).displayName,
                typeID: typeID,
                appearance: defaultAppearance(for: typeID),
                duration: typeID == .timer ? timerPresets.first : nil)
        }
        return builtIn + customPresets
    }
}
