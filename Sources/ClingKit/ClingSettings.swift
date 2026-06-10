/**
 App-wide preferences, persisted via `ClingStore` so future extensions read the
 same defaults. Decoding is field-by-field with fallbacks so adding a setting
 never invalidates an existing settings file.
 */
import Foundation

public struct ClingSettings: Codable, Equatable, Sendable {
    /// The default appearance a new pin of each type starts from. Users tune
    /// these once and every future pin inherits the look.
    public var defaultAppearances: [PinTypeID: PinAppearance]
    /// Schedule "expires soon — keep it alive?" local notifications.
    public var renewalRemindersEnabled: Bool
    /// The duration chips offered in the timer quick-add.
    public var timerPresets: [TimeInterval]
    /// Accent for the app's own chrome (backdrop glow, card tint).
    public var appAccent: RGBA
    /// User-saved builder presets, shown after the built-in four.
    public var customPresets: [PinPreset]

    public static let `default` = ClingSettings(
        defaultAppearances: [
            .note: PinAppearance(accent: PinAppearance.indigo, symbolName: "note.text"),
            .timer: PinAppearance(accent: PinAppearance.ember, symbolName: "timer"),
            .parking: PinAppearance(accent: PinAppearance.sky, symbolName: "car.fill"),
            .clipboard: PinAppearance(accent: PinAppearance.mint, symbolName: "doc.on.clipboard"),
        ],
        renewalRemindersEnabled: true,
        timerPresets: [5 * 60, 15 * 60, 25 * 60, 60 * 60],
        appAccent: PinAppearance.indigo
    )

    public init(
        defaultAppearances: [PinTypeID: PinAppearance],
        renewalRemindersEnabled: Bool,
        timerPresets: [TimeInterval],
        appAccent: RGBA,
        customPresets: [PinPreset] = []
    ) {
        self.defaultAppearances = defaultAppearances
        self.renewalRemindersEnabled = renewalRemindersEnabled
        self.timerPresets = timerPresets
        self.appAccent = appAccent
        self.customPresets = customPresets
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
        case defaultAppearances, renewalRemindersEnabled, timerPresets, appAccent, customPresets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        defaultAppearances = (try? c.decode([PinTypeID: PinAppearance].self, forKey: .defaultAppearances)) ?? d.defaultAppearances
        renewalRemindersEnabled = (try? c.decode(Bool.self, forKey: .renewalRemindersEnabled)) ?? d.renewalRemindersEnabled
        timerPresets = (try? c.decode([TimeInterval].self, forKey: .timerPresets)) ?? d.timerPresets
        appAccent = (try? c.decode(RGBA.self, forKey: .appAccent)) ?? d.appAccent
        customPresets = (try? c.decode([PinPreset].self, forKey: .customPresets)) ?? []
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
