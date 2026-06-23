/**
 The pin-type plugin contract. One conforming type per pin type, registered in
 `PinRegistry`, owning everything type-specific: glyph, validation, the
 quick-add form, the list row, and every Live Activity presentation.

 `AnyView` at this boundary is deliberate: the registry is heterogeneous, the
 view trees are tiny, and Live Activity views are re-rendered wholesale by the
 system — there's no diffing win to protect.

 Adding a pin type = a `PinPayload` case (the compiler then walks you through
 every exhaustive switch), one new file conforming to this protocol, and one
 registry line. See ARCHITECTURE.md.
 */
import SwiftUI

/// Everything a renderer needs, decoded once from activity attributes + state.
/// Deliberately free of ActivityKit types so the same renderers serve in-app
/// previews (the appearance editor shows the literal activity views).
public struct PinRenderContext: Sendable {
    public let pinID: UUID
    public let payload: PinPayload
    public let appearance: PinAppearance
    /// When the activity goes stale — nil in contexts without one (in-app
    /// previews). Renderers may surface it; the shared lock-screen chrome
    /// already does.
    public let staleDate: Date?

    public init(pinID: UUID, payload: PinPayload, appearance: PinAppearance, staleDate: Date? = nil) {
        self.pinID = pinID
        self.payload = payload
        self.appearance = appearance
        self.staleDate = staleDate
    }

    /// Convenience for renderers.
    public var accent: Color { appearance.accent.color }
    public var density: LayoutDensity { appearance.density }
}

public extension PinSnapshot {
    /// The render context this snapshot describes — the same struct in-app
    /// previews use, so a roster row and the appearance editor draw identically.
    var renderContext: PinRenderContext {
        PinRenderContext(
            pinID: id, payload: payload,
            appearance: appearance, staleDate: staleDate)
    }
}

/// The in-progress state of the quick-add composer — one shared draft struct
/// (rather than per-type generics) so the composer can switch types without
/// losing what's already typed.
public struct PinDraft: Sendable, Equatable {
    public var typeID: PinTypeID
    /// Note text.
    public var text: String
    /// Timer label.
    public var label: String
    /// How the timer's countdown draws — see `CountdownStyle`.
    public var countdownStyle: CountdownStyle
    /// Parking headline override ("Parked here" when empty).
    public var title: String
    public var duration: TimeInterval
    /// Parking fields — filled by app-side location/photo pickers.
    public var parkingNote: String
    public var latitude: Double?
    public var longitude: Double?
    public var photoFilename: String?
    /// Note provenance, when shared from a web page.
    public var sourceURL: URL?
    /// Optional caption for a decorative pin.
    public var decorLabel: String
    /// Optional second glyph for a decorative pin, drawn on the trailing side of
    /// the Dynamic Island. Empty = none (caption takes the slot instead).
    public var decorTrailingSymbol: String
    /// Match pin: the two teams' FIFA codes ("ARG", "FRA"). A manually-created
    /// match starts 0–0, scheduled — a live feed takes over the score via push.
    public var matchHomeCode: String
    public var matchAwayCode: String
    /// Fight pin: the focused bout's two fighters + the event name. A live feed
    /// takes over round/clock/result via push.
    public var fightRedName: String
    public var fightBlueName: String
    public var fightEventName: String
    /// Game pin: which US league + the two team codes. A live feed takes over
    /// the score/period/clock via push.
    public var gameLeague: SportLeague
    public var gameHomeAbbr: String
    public var gameAwayAbbr: String
    /// Ticker pin: the symbol the user types + whether it's a stock or crypto.
    /// The quote API fills in the name, price, change and sparkline.
    public var tickerSymbol: String
    public var tickerMarket: TickerMarket

    public init(typeID: PinTypeID = .note) {
        self.typeID = typeID
        self.text = ""
        self.label = ""
        self.countdownStyle = .text
        self.title = ""
        self.duration = 15 * 60
        self.parkingNote = ""
        self.decorLabel = ""
        self.decorTrailingSymbol = ""
        self.matchHomeCode = ""
        self.matchAwayCode = ""
        self.fightRedName = ""
        self.fightBlueName = ""
        self.fightEventName = ""
        self.gameLeague = .nba
        self.gameHomeAbbr = ""
        self.gameAwayAbbr = ""
        self.tickerSymbol = ""
        self.tickerMarket = .stock
    }

    /// The payload this draft describes, or nil while it's incomplete.
    public func payload(now: Date = .now) -> PinPayload? {
        switch typeID {
        case .note:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || photoFilename != nil else { return nil }
            return .note(NotePayload(text: trimmed, photoFilename: photoFilename, sourceURL: sourceURL))
        case .timer:
            guard duration > 0 else { return nil }
            return .timer(TimerPayload(
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: now,
                endDate: now.addingTimeInterval(duration),
                style: countdownStyle))
        case .parking:
            guard let latitude, let longitude else { return nil }
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = parkingNote.trimmingCharacters(in: .whitespacesAndNewlines)
            return .parking(ParkingPayload(
                latitude: latitude, longitude: longitude,
                title: title.isEmpty ? nil : title,
                note: note.isEmpty ? nil : note,
                photoFilename: photoFilename))
        case .decor:
            // Always valid — a decoration needs no content, just a glyph.
            let caption = decorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let trailing = decorTrailingSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
            return .decor(DecorPayload(
                label: caption.isEmpty ? nil : caption,
                trailingSymbol: trailing.isEmpty ? nil : trailing))
        case .match:
            let home = MatchPayload.normalizeCode(matchHomeCode)
            let away = MatchPayload.normalizeCode(matchAwayCode)
            guard !home.isEmpty, !away.isEmpty else { return nil }
            return .match(MatchPayload(homeCode: home, awayCode: away))
        case .fight:
            let red = fightRedName.trimmingCharacters(in: .whitespacesAndNewlines)
            let blue = fightBlueName.trimmingCharacters(in: .whitespacesAndNewlines)
            let event = fightEventName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !red.isEmpty, !blue.isEmpty else { return nil }
            return .fight(FightPayload(
                eventName: event.isEmpty ? "UFC" : event,
                redName: red, blueName: blue))
        case .game:
            // The unified Game composer spans every team sport. World Cup is
            // still a football match under the hood (flags + minute + the
            // soccer renderer), so it routes to a `.match` payload; the four US
            // leagues stay `.game`. Picking the league is the only fork.
            let home = TeamGamePayload.normalizeAbbr(gameHomeAbbr)
            let away = TeamGamePayload.normalizeAbbr(gameAwayAbbr)
            guard !home.isEmpty, !away.isEmpty else { return nil }
            if gameLeague == .worldCup {
                let hc = MatchPayload.normalizeCode(home)
                let ac = MatchPayload.normalizeCode(away)
                guard !hc.isEmpty, !ac.isEmpty else { return nil }
                return .match(MatchPayload(
                    homeCode: hc, awayCode: ac,
                    homeName: LeagueTeams.team(abbr: hc, in: .worldCup)?.name ?? "",
                    awayName: LeagueTeams.team(abbr: ac, in: .worldCup)?.name ?? ""))
            }
            guard let sport = gameLeague.gameSport else { return nil }
            return .game(TeamGamePayload(
                sport: sport, league: gameLeague.path, leagueName: gameLeague.label,
                homeAbbr: home, awayAbbr: away))
        case .ticker:
            let sym = TickerPayload.normalizeSymbol(tickerSymbol)
            guard sym.count >= 1 else { return nil }
            return .ticker(TickerPayload(
                symbol: sym, market: tickerMarket,
                sourceID: TickerPayload.makeSourceID(market: tickerMarket, symbol: sym)))
        }
    }
}

@MainActor
public protocol PinModule {
    static var typeID: PinTypeID { get }
    static var displayName: String { get }
    /// The type's default glyph (users can swap it per pin).
    static var systemImage: String { get }
    /// The SF Symbols offered for this type in the appearance editor.
    static var symbolChoices: [String] { get }

    /// Whether this type appears as its own entry in the quick-add type
    /// switcher. A type can still exist (render, decode, reconcile) without
    /// being independently creatable — e.g. World Cup matches are now created
    /// through the unified Game form, so `MatchPinModule` is hidden here while
    /// its renderers and payload keep serving existing/soccer pins.
    static var isCreatable: Bool { get }

    /// nil when valid; a user-facing message otherwise.
    static func validate(_ payload: PinPayload) -> String?

    // App-side views

    /// The type-specific fields of the quick-add composer.
    static func quickAddForm(draft: Binding<PinDraft>) -> AnyView
    /// The pin's row in the main list.
    static func listRow(_ pin: Pin) -> AnyView

    // Live Activity views — run in the widget process; must not touch app
    // state. iUX glass modifiers and tokens are safe; navigation is not.

    static func lockScreen(_ ctx: PinRenderContext) -> AnyView
    static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView
    static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView
    static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView
    /// Optional bottom region of the expanded island; nil to omit.
    static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView?
    static func diCompactLeading(_ ctx: PinRenderContext) -> AnyView
    static func diCompactTrailing(_ ctx: PinRenderContext) -> AnyView
    static func diMinimal(_ ctx: PinRenderContext) -> AnyView

    /// A single compact row for the multi-pin roster — shown in the expanded
    /// island and the lock-screen card when more than one pin is live: glyph +
    /// title, plus the type's inline primary action (Walk / Copy / countdown).
    static func liveRow(_ ctx: PinRenderContext) -> AnyView

    /// True when `liveRow` contains its own interactive control (a `Link` /
    /// `Button`). The roster must NOT then wrap the row in an outer tap target:
    /// nesting two interactive elements is invalid SwiftUI and renders the whole
    /// Live Activity blank. Default false (the roster owns the row's tap).
    static var liveRowHasInlineAction: Bool { get }
}

public extension PinModule {
    /// Most types validate at draft time; payloads are well-formed by
    /// construction. Override for types with semantic constraints (e.g. a
    /// timer whose end must be in the future).
    static func validate(_ payload: PinPayload) -> String? { nil }

    /// Most types are creatable on their own; override to `false` to keep a type
    /// renderable but out of the quick-add switcher.
    static var isCreatable: Bool { true }

    static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView? { nil }

    /// Most rows carry no interactive control, so the roster wraps them in a
    /// detail link. Types whose `liveRow` embeds its own `Link`/`Button` override
    /// this to true so the roster leaves the tap to them (no nested controls).
    static var liveRowHasInlineAction: Bool { false }

    /// Shared minimal presentation: the pin's glyph in its accent. Types
    /// override only when they have something more glanceable (a countdown).
    static func diMinimal(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Image(systemName: ctx.appearance.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ctx.accent)
        )
    }

    /// Glyph + display name, no action. Types override to add their title and
    /// inline action; this keeps an unregistered or actionless type renderable.
    static func liveRow(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                PinGlyph(appearance: ctx.appearance, size: 30)
                Text(displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
        )
    }
}
