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

/// How a fresh play-by-play line interrupts. A non-silent update is an alerting
/// push, which momentarily expands the Dynamic Island (the only way to force the
/// expanded look) instead of refreshing it silently. `off` keeps every line
/// silent; `important` only expands for meaningful events (goal/card/penalty/
/// VAR); `all` expands on every line (~1/min — burns more of the update budget).
public enum MatchCommentaryAlerts: String, Codable, CaseIterable, Sendable {
    case off, important, all

    public var displayName: String {
        switch self {
        case .off:       "Never"
        case .important: "Key moments"
        case .all:       "Every line"
        }
    }
}

public struct ClingSettings: Codable, Equatable, Sendable {
    /// The default appearance a new pin of each type starts from. Surface,
    /// type, density, border, accent, and glyph are all per-type.
    public var defaultAppearances: [PinTypeID: PinAppearance]
    /// Legacy house style — folded into `defaultAppearances` on load; kept in
    /// the store for forward-compatible decoding only.
    public var globalStyle: GlobalPinStyle
    /// Schedule "expires soon — keep it alive?" local notifications.
    public var renewalRemindersEnabled: Bool
    /// Show the live play-by-play line under a match score ("… takes a throw-in").
    /// Read by the match renderer; off falls back to the quieter score-only card.
    public var matchPlayByPlay: Bool
    /// Whether a fresh commentary line should expand the Dynamic Island (an
    /// alerting push) and, if so, for which lines. Sent to the push server so it
    /// alerts on the matching closed-app commentary push. See `MatchCommentaryAlerts`.
    public var matchCommentaryAlerts: MatchCommentaryAlerts
    /// Whether a commentary auto-expand also plays the default sound + haptic.
    /// Off = silent banner that still expands the island. Sent to the server.
    public var matchCommentaryAlertSound: Bool
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
            .match: PinAppearance(accent: PinAppearance.mint, symbolName: "sportscourt.fill"),
            .fight: PinAppearance(accent: PinAppearance.ember, symbolName: "figure.martial.arts"),
            .game: PinAppearance(accent: PinAppearance.mint, symbolName: "sportscourt.fill"),
            .ticker: PinAppearance(accent: RGBA(hex: 0x32D74B), symbolName: "chart.line.uptrend.xyaxis"),
        ],
        globalStyle: .default,
        renewalRemindersEnabled: true,
        timerPresets: [5 * 60, 15 * 60, 25 * 60, 60 * 60],
        appAccent: PinAppearance.indigo,
        matchPlayByPlay: true
    )

    public init(
        defaultAppearances: [PinTypeID: PinAppearance],
        globalStyle: GlobalPinStyle = .default,
        renewalRemindersEnabled: Bool,
        timerPresets: [TimeInterval],
        appAccent: RGBA,
        customPresets: [PinPreset] = [],
        mapProvider: MapProvider = .apple,
        matchPlayByPlay: Bool = true,
        matchCommentaryAlerts: MatchCommentaryAlerts = .important,
        matchCommentaryAlertSound: Bool = false
    ) {
        self.defaultAppearances = defaultAppearances
        self.globalStyle = globalStyle
        self.renewalRemindersEnabled = renewalRemindersEnabled
        self.timerPresets = timerPresets
        self.appAccent = appAccent
        self.customPresets = customPresets
        self.mapProvider = mapProvider
        self.matchPlayByPlay = matchPlayByPlay
        self.matchCommentaryAlerts = matchCommentaryAlerts
        self.matchCommentaryAlertSound = matchCommentaryAlertSound
    }

    /// Returns the appearance as stored — per-type fields are the source of truth.
    public func styled(_ base: PinAppearance) -> PinAppearance {
        base
    }

    /// One-time migration: fold a saved global style into every per-type default
    /// and reset the global knob so it isn't applied twice.
    public mutating func foldGlobalStyleIntoDefaults() {
        let style = globalStyle
        guard style != .default else { return }
        for typeID in PinTypeID.allCases {
            var base = defaultAppearance(for: typeID)
            defaultAppearances[typeID] = style.apply(to: base)
        }
        globalStyle = .default
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
        case defaultAppearances, globalStyle, renewalRemindersEnabled, timerPresets, appAccent, customPresets, mapProvider, matchPlayByPlay
        case matchCommentaryAlerts, matchCommentaryAlertSound
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
        matchPlayByPlay = (try? c.decode(Bool.self, forKey: .matchPlayByPlay)) ?? d.matchPlayByPlay
        matchCommentaryAlerts = (try? c.decode(MatchCommentaryAlerts.self, forKey: .matchCommentaryAlerts)) ?? d.matchCommentaryAlerts
        matchCommentaryAlertSound = (try? c.decode(Bool.self, forKey: .matchCommentaryAlertSound)) ?? d.matchCommentaryAlertSound
    }

    /// The builder's preset row: one built-in per type (wearing the user's
    /// per-type default look), then the user's saved customs.
    @MainActor
    public func builderPresets() -> [PinPreset] {
        let builtIn = PinTypeID.allCases.filter {
            PinRegistry.module(for: $0).isCreatable
        }.map { typeID in
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
