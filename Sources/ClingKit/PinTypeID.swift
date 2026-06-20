/**
 The identity of a pin type. One case per type; the raw value is the wire
 format in `cling-pins.v1.json` and in Live Activity attributes, so cases are
 add-only — never rename or remove a shipped one.
 */
import Foundation

public enum PinTypeID: String, Codable, Sendable, Hashable, CaseIterable {
    case note
    case timer
    case parking
    /// A content-free pin that exists only to dress the Dynamic Island — a
    /// glyph in the house style, with an optional short caption.
    case decor
}
