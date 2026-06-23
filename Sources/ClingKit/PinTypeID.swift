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
    /// A live football match — two teams, score, and minute — kept current in
    /// the Dynamic Island by server-pushed Live Activity updates.
    case match
    /// A live UFC event — follows the card's current bout (fighters, round,
    /// clock, result), kept current by server-pushed Live Activity updates.
    case fight
    /// A live team game — two teams, score, and period/clock — covering the US
    /// leagues (NBA/NFL/NHL/MLB) off ESPN's uniform scoreboard. Kept current by
    /// server-pushed Live Activity updates.
    case game
    /// A tracked market quote — one stock or crypto symbol with its live price,
    /// day change and an intraday sparkline. Price comes from a quote API; it
    /// refreshes via server-pushed Live Activity updates, so a move lands in the
    /// island with Cling closed.
    case ticker
}
