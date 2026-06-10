/**
 `PinPreset`: a ready-to-go pin configuration — type + look (+ a default
 duration for timers). The builder offers four built-ins (one per type, wearing
 the user's per-type default appearance) and any customs the user has saved
 ("Pasta · 12 min · ember serif").
 */
import Foundation

public struct PinPreset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var typeID: PinTypeID
    public var appearance: PinAppearance
    /// Timer presets carry their duration; nil for other types.
    public var duration: TimeInterval?

    public init(
        id: UUID = UUID(),
        name: String,
        typeID: PinTypeID,
        appearance: PinAppearance,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.name = String(name.prefix(40))
        self.typeID = typeID
        self.appearance = appearance
        self.duration = duration
    }
}
