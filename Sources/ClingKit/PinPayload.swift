/**
 `PinPayload`: the typed content of a pin, one case per pin type.

 ActivityKit binds each Live Activity configuration to ONE concrete
 `ActivityAttributes` type, so heterogeneous pins travel as this Codable enum
 and fan out to per-type renderers at the view layer (see `PinModule`).

 Size discipline: the encoded payload rides in the activity's `ContentState`,
 which iOS caps around 4KB. Text fields are clamped at creation and images are
 NEVER embedded — only filenames pointing into the App Group container.
 */
import Foundation

public enum PinPayload: Codable, Hashable, Sendable {
    case note(NotePayload)
    case timer(TimerPayload)
    case parking(ParkingPayload)
    case decor(DecorPayload)
    case match(MatchPayload)
    case fight(FightPayload)
    case game(TeamGamePayload)
    case ticker(TickerPayload)

    public var typeID: PinTypeID {
        switch self {
        case .note:      .note
        case .timer:     .timer
        case .parking:   .parking
        case .decor:     .decor
        case .match:     .match
        case .fight:     .fight
        case .game:      .game
        case .ticker:    .ticker
        }
    }

    /// The scheduled start of a time-anchored pin, used to order the board so
    /// sooner events sit above ones still days out. Nil for pins with no fixed
    /// kickoff (notes, running timers, parking, decor, tickers), which fall back
    /// to creation order.
    public var scheduledStart: Date? {
        switch self {
        case .fight(let p): p.startDate
        case .game(let p):  p.startTime
        case .match(let p): p.kickoff
        case .note, .timer, .parking, .decor, .ticker: nil
        }
    }
}

/// A live sport, identified by its ESPN scoreboard path. This is the seam that
/// makes the live-sports plumbing generic: the feed client, the foreground
/// poller and the push Worker all key off the `path`, so a new sport is a new
/// case here plus a payload + renderer — never a change to the transport.
public enum SportLeague: String, Codable, Hashable, Sendable, CaseIterable {
    case worldCup
    case ufc
    case nba
    case nfl
    case nhl
    case mlb

    /// The ESPN `…/sports/<path>/scoreboard` segment.
    public var path: String {
        switch self {
        case .worldCup: "soccer/fifa.world"
        case .ufc:      "mma/ufc"
        case .nba:      "basketball/nba"
        case .nfl:      "football/nfl"
        case .nhl:      "hockey/nhl"
        case .mlb:      "baseball/mlb"
        }
    }

    /// Human label for the browser's sport switcher (also the in-pin league tag).
    public var label: String {
        switch self {
        case .worldCup: "World Cup"
        case .ufc:      "UFC"
        case .nba:      "NBA"
        case .nfl:      "NFL"
        case .nhl:      "NHL"
        case .mlb:      "MLB"
        }
    }

    public var systemImage: String {
        switch self {
        case .worldCup: "soccerball"
        case .ufc:      "figure.martial.arts"
        case .nba:      "basketball.fill"
        case .nfl:      "football.fill"
        case .nhl:      "hockey.puck.fill"
        case .mlb:      "baseball.fill"
        }
    }

    /// The team-game sport this league produces, or nil for the leagues with
    /// their own pin type (soccer → `.match`, UFC → `.fight`). The four US
    /// leagues all share the one `TeamGamePayload`/`GamePinModule`; this is the
    /// only thing that varies the period semantics between them.
    public var gameSport: GameSport? {
        switch self {
        case .nba:      .basketball
        case .nfl:      .football
        case .nhl:      .hockey
        case .mlb:      .baseball
        case .worldCup, .ufc: nil
        }
    }
}

/// Which clock model a team game runs on — the one axis that differs between
/// NBA/NFL (quarters), NHL (periods) and MLB (innings, no clock).
public enum GameSport: String, Codable, Hashable, Sendable {
    case basketball
    case football
    case hockey
    case baseball

    /// The short tag for a numbered period: "Q3", "P2", "5th".
    func periodTag(_ n: Int) -> String {
        switch self {
        case .basketball, .football: return n > 4 ? "OT" : "Q\(n)"
        case .hockey:                return n > 3 ? "OT" : "P\(n)"
        case .baseball:              return ordinal(n)
        }
    }

    /// Whether a running game clock is meaningful (baseball has none).
    var hasClock: Bool { self != .baseball }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}

/// The state of a team game, mapped from the feed's status codes onto four
/// glanceable buckets — twin of `MatchStatus`.
public enum GameStatus: String, Codable, Hashable, Sendable {
    case scheduled
    case live
    case halftime
    case finished
}

/// The prematch glance shared by team games and football matches: local start
/// time plus a one-shot "in 2h" — "Starts 19:30 · in 2h". Live Activity centers
/// use `Text(_:style:.relative)` instead so the countdown ticks client-side
/// without a push; this snapshot string is for the list rows and the browser.
private func prematchLine(_ start: Date, now: Date) -> String {
    let clock = DateFormatter()
    clock.dateFormat = "HH:mm"
    let rel = RelativeDateTimeFormatter()
    rel.unitsStyle = .short
    return "Starts \(clock.string(from: start)) · \(rel.localizedString(for: start, relativeTo: now))"
}

/// A live team game pinned to the Dynamic Island: two teams, the score, and the
/// period/clock. Covers the US leagues (NBA/NFL/NHL/MLB) off ESPN's uniform
/// scoreboard shape; the per-sport clock model rides in `sport`. Score, period
/// and clock change via Live Activity updates pushed from the server, so a
/// basket lands in the island with Cling closed.
///
/// Teams travel as their league abbreviations (`LAL`, `BOS`) — logos can't ride
/// a 4KB push, so the renderer shows the codes.
public struct TeamGamePayload: Codable, Hashable, Sendable {
    public var sport: GameSport
    /// ESPN scoreboard path (`basketball/nba`) — the sport-agnostic seam.
    public var league: String
    /// Short league tag for the card subtitle ("NBA").
    public var leagueName: String
    public var homeAbbr: String
    public var awayAbbr: String
    public var homeScore: Int
    public var awayScore: Int
    /// Quarter / period / inning number when live; nil otherwise.
    public var period: Int?
    /// Running game clock ("5:21") when live and the sport has one; nil for
    /// baseball and stopped play.
    public var clock: String?
    /// A sport-specific live detail the period number can't carry — baseball's
    /// "Top 5th" / "Bot 7th". nil when the period tag says enough.
    public var situation: String?
    public var status: GameStatus
    public var startTime: Date
    /// ESPN event id — the poller/Worker reconcile against this.
    public var sourceID: String?

    public init(
        sport: GameSport,
        league: String,
        leagueName: String,
        homeAbbr: String,
        awayAbbr: String,
        homeScore: Int = 0,
        awayScore: Int = 0,
        period: Int? = nil,
        clock: String? = nil,
        situation: String? = nil,
        status: GameStatus = .scheduled,
        startTime: Date = .now,
        sourceID: String? = nil
    ) {
        self.sport = sport
        self.league = league
        self.leagueName = String(leagueName.prefix(8))
        self.homeAbbr = TeamGamePayload.normalizeAbbr(homeAbbr)
        self.awayAbbr = TeamGamePayload.normalizeAbbr(awayAbbr)
        self.homeScore = max(0, homeScore)
        self.awayScore = max(0, awayScore)
        self.period = period.map { max(1, $0) }
        self.clock = clock
        self.situation = situation.map { String($0.prefix(16)) }
        self.status = status
        self.startTime = startTime
        self.sourceID = sourceID
    }

    /// The same game with fresh live numbers from the feed — preserves the
    /// teams/league/identity, swaps what changes during play.
    public func updatingState(
        homeScore: Int, awayScore: Int, period: Int?, clock: String?,
        situation: String?, status: GameStatus
    ) -> TeamGamePayload {
        TeamGamePayload(
            sport: sport, league: league, leagueName: leagueName,
            homeAbbr: homeAbbr, awayAbbr: awayAbbr,
            homeScore: homeScore, awayScore: awayScore,
            period: period, clock: clock, situation: situation,
            status: status, startTime: startTime, sourceID: sourceID)
    }

    /// Abbreviations are upper-cased and clamped so the renderer gets a clean key.
    static func normalizeAbbr(_ raw: String) -> String {
        String(raw.uppercased().filter(\.isLetter).prefix(4))
    }

    // MARK: Display

    /// The center-of-island score, en-dash separated, home first: "104–98".
    public var scoreText: String { "\(homeScore)–\(awayScore)" }

    /// Local clock time the game starts ("19:30") — the prematch island glance.
    public var startClock: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: startTime)
    }

    public var isLive: Bool { status == .live || status == .halftime }

    /// The glanceable period/clock — "Q3 5:21", "Top 5th", "Half", "Final", or
    /// the prematch "Starts 19:30 · in 2h" before tip-off.
    public func statusLine(now: Date = .now) -> String {
        switch status {
        case .halftime: return "Half"
        case .finished: return "Final"
        case .scheduled:
            return prematchLine(startTime, now: now)
        case .live:
            if sport == .baseball { return situation ?? period.map { sport.periodTag($0) } ?? "LIVE" }
            guard let period else { return "LIVE" }
            let tag = sport.periodTag(period)
            return clock.map { "\(tag) \($0)" } ?? tag
        }
    }
}

/// The state of a football match, mapped server-side from the data feed's
/// status codes onto these four glanceable buckets. The raw minute rides
/// separately so the island can read "67'".
public enum MatchStatus: String, Codable, Hashable, Sendable {
    /// Not started — the island shows kickoff time.
    case scheduled
    /// In play — the island shows the running minute.
    case live
    /// Half-time break.
    case halftime
    /// Play stopped mid-match (crowd trouble, weather, floodlight failure) and
    /// not yet resumed. The feed freezes the minute, so the island shows "Susp."
    /// rather than a stale running clock.
    case suspended
    /// Full time / finished.
    case finished
}

/// A live football match pinned to the Dynamic Island: two teams, the score,
/// and where the match is. The score and minute change via Live Activity
/// updates (a server pushes new `ContentState` over APNs — see
/// `ActivityPushContract`), so a goal updates the island with Cling closed.
///
/// Teams travel as FIFA 3-letter codes (`ARG`, `FRA`) — crest images can't ride
/// a 4KB push payload, so the renderer turns the code into a flag emoji
/// client-side. The full name rides for the roomier lock-screen card.
public struct MatchPayload: Codable, Hashable, Sendable {
    public var homeCode: String
    public var awayCode: String
    public var homeName: String
    public var awayName: String
    public var homeScore: Int
    public var awayScore: Int
    /// Elapsed minutes when `status == .live`; nil otherwise.
    public var minute: Int?
    public var status: MatchStatus
    /// "World Cup", "Group C" — the competition/stage label.
    public var competition: String
    public var kickoff: Date
    /// The data feed's stable id for this fixture (ESPN event id). Lets the
    /// foreground poller and the push server reconcile a pin against the feed
    /// to push a new score. nil for a hand-made match with no feed behind it.
    public var sourceID: String?
    /// The ESPN scoreboard path this fixture lives on (`soccer/fifa.world`).
    /// Carried so the poller and Worker know which feed to poll — the one field
    /// that makes the live-sports plumbing sport-agnostic (see `SportLeague`).
    public var league: String
    /// The latest play-by-play line from the feed — "Maxim De Cuyper takes a
    /// throw-in." A short, push-cheap commentary string the renderer shows under
    /// the score when the user's play-by-play setting is on. It rides along on
    /// the ~1/min minute-tick push rather than triggering its own (a throw-in
    /// feed would otherwise burn the Live Activity update budget). nil for
    /// hand-made matches and feeds that don't carry commentary.
    public var lastEvent: String?
    /// Wall-clock instant the `minute` was sampled (set by the push server and
    /// the foreground poll). Lets the renderer draw a self-ticking clock that
    /// keeps advancing between the ~1/min pushes instead of freezing on the last
    /// pushed integer — each push re-anchors it against the feed's true minute.
    /// nil for hand-made matches and pre-`minuteAsOf` stored pins.
    public var minuteAsOf: Date?

    public init(
        homeCode: String,
        awayCode: String,
        homeName: String = "",
        awayName: String = "",
        homeScore: Int = 0,
        awayScore: Int = 0,
        minute: Int? = nil,
        status: MatchStatus = .scheduled,
        competition: String = "World Cup",
        kickoff: Date = .now,
        sourceID: String? = nil,
        league: String = SportLeague.worldCup.path,
        lastEvent: String? = nil,
        minuteAsOf: Date? = nil
    ) {
        self.homeCode = MatchPayload.normalizeCode(homeCode)
        self.awayCode = MatchPayload.normalizeCode(awayCode)
        self.homeName = String(homeName.prefix(40))
        self.awayName = String(awayName.prefix(40))
        self.homeScore = max(0, homeScore)
        self.awayScore = max(0, awayScore)
        self.minute = minute.map { max(0, $0) }
        self.status = status
        self.competition = String(competition.prefix(40))
        self.kickoff = kickoff
        self.sourceID = sourceID
        self.league = league
        // Safety cap above the server's word-boundary clamp (160 + ellipsis), so
        // a long goal line arrives whole and the renderer tail-truncates it.
        self.lastEvent = lastEvent.map { String($0.prefix(200)) }
        self.minuteAsOf = minuteAsOf
    }

    // Forward-compatible: pins stored before `league`/`lastEvent` existed lack
    // the key, so default rather than failing the whole store.
    private enum CodingKeys: String, CodingKey {
        case homeCode, awayCode, homeName, awayName, homeScore, awayScore
        case minute, status, competition, kickoff, sourceID, league, lastEvent, minuteAsOf
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        homeCode = try c.decode(String.self, forKey: .homeCode)
        awayCode = try c.decode(String.self, forKey: .awayCode)
        homeName = try c.decode(String.self, forKey: .homeName)
        awayName = try c.decode(String.self, forKey: .awayName)
        homeScore = try c.decode(Int.self, forKey: .homeScore)
        awayScore = try c.decode(Int.self, forKey: .awayScore)
        minute = try c.decodeIfPresent(Int.self, forKey: .minute)
        status = try c.decode(MatchStatus.self, forKey: .status)
        competition = try c.decode(String.self, forKey: .competition)
        kickoff = try c.decode(Date.self, forKey: .kickoff)
        sourceID = try c.decodeIfPresent(String.self, forKey: .sourceID)
        league = (try? c.decode(String.self, forKey: .league)) ?? SportLeague.worldCup.path
        lastEvent = try c.decodeIfPresent(String.self, forKey: .lastEvent)
        minuteAsOf = try c.decodeIfPresent(Date.self, forKey: .minuteAsOf)
    }

    /// The same match with fresh live numbers from the feed — preserves the
    /// teams/competition/identity (and any pushed `lastEvent`), swaps what
    /// changes during play. The foreground scoreboard poll carries no commentary,
    /// so it keeps whatever the server last pushed rather than wiping it.
    public func updatingScore(
        homeScore: Int, awayScore: Int, minute: Int?, status: MatchStatus
    ) -> MatchPayload {
        MatchPayload(
            homeCode: homeCode, awayCode: awayCode,
            homeName: homeName, awayName: awayName,
            homeScore: homeScore, awayScore: awayScore,
            minute: minute, status: status,
            competition: competition, kickoff: kickoff, sourceID: sourceID,
            league: league, lastEvent: lastEvent,
            // The foreground poll just sampled this minute — re-anchor the live
            // clock so it ticks forward from now rather than the last push.
            minuteAsOf: status == .live ? .now : nil)
    }

    /// Codes are upper-cased and clamped to 3 chars so the renderer and the
    /// flag lookup get a clean key.
    static func normalizeCode(_ raw: String) -> String {
        String(raw.uppercased().filter(\.isLetter).prefix(3))
    }

    // MARK: Display

    /// The center-of-island score, en-dash separated: "2–1".
    public var scoreText: String { "\(homeScore)–\(awayScore)" }

    /// Local clock time the match kicks off ("19:30") — the prematch island glance.
    public var kickoffClock: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: kickoff)
    }

    /// Home name when present, else the code — for the lock-screen card.
    public var homeLabel: String { homeName.isEmpty ? homeCode : homeName }
    public var awayLabel: String { awayName.isEmpty ? awayCode : awayName }

    /// The line under the score: running minute, HT, FT, or the prematch
    /// "Starts 19:30 · in 2h" before kickoff.
    public func statusLine(now: Date = .now) -> String {
        switch status {
        case .live:      return minute.map { "\($0)'" } ?? "LIVE"
        case .halftime:  return "HT"
        case .suspended: return "Susp."
        case .finished:  return "FT"
        case .scheduled:
            return prematchLine(kickoff, now: now)
        }
    }

    /// Whether the match is currently being played or on a break (drives the
    /// status dot and whether the minute is worth showing).
    public var isLive: Bool { status == .live || status == .halftime }

    /// Anchor for a self-ticking live clock: the wall-clock instant at which the
    /// match minute read 0:00, so `Text(anchor, style: .timer)` displays the
    /// running minute and keeps counting between the ~1/min pushes that
    /// re-anchor it. nil unless live with a sampled minute — the clock can run
    /// slightly ahead during halftime/stoppage until the next push corrects it.
    public var liveClockAnchor: Date? {
        guard status == .live, let asOf = minuteAsOf else { return nil }
        return asOf.addingTimeInterval(-Double((minute ?? 0) * 60))
    }

    /// A flag emoji for a FIFA 3-letter code, or a soccer ball when unmapped.
    public static func flag(for fifaCode: String) -> String {
        FIFAFlags.emoji[normalizeCode(fifaCode)] ?? "⚽️"
    }

    public var homeFlag: String { MatchPayload.flag(for: homeCode) }
    public var awayFlag: String { MatchPayload.flag(for: awayCode) }
}

/// Which corner won the focused bout.
public enum FightCorner: String, Codable, Hashable, Sendable { case red, blue }

/// Card-level state of a UFC event.
public enum FightStatus: String, Codable, Hashable, Sendable {
    /// No bout under way yet — the island shows the card start time.
    case upcoming
    /// A bout is in progress — the island shows its round + clock.
    case live
    /// The card (or the focused bout) is over.
    case finished
}

/// A live UFC event pinned to the Dynamic Island. Unlike a football match, the
/// pin follows the **card**: it always shows whichever bout is currently in
/// play (auto-advancing as the night moves on), or the next bout before the
/// card starts, or the main event once it's done. The round, clock and result
/// change via Live Activity updates pushed from the server (see
/// `ActivityPushContract`), so a finish lands in the island with Cling closed.
///
/// Fighters travel as names (no flags/codes — MMA isn't nation-coded); the
/// renderer shows last names where space is tight.
public struct FightPayload: Codable, Hashable, Sendable {
    /// "UFC Fight Night: Kape vs. Horiguchi 2".
    public var eventName: String
    /// The two fighters of the focused bout (red corner first).
    public var redName: String
    public var blueName: String
    /// Current round when `status == .live`; nil otherwise.
    public var round: Int?
    /// Round clock as the feed reports it ("3:24"); nil when not live.
    public var clock: String?
    /// The focused bout's slot/weight ("Main Event", "Flyweight").
    public var boutName: String
    public var status: FightStatus
    /// Winning corner once the focused bout is decided.
    public var winner: FightCorner?
    /// How it ended ("KO/TKO", "Submission", "Decision"); nil until decided.
    public var method: String?
    /// ESPN event (card) id — the poller/Worker reconcile against this.
    public var sourceID: String?
    /// ESPN scoreboard path — `SportLeague.ufc.path`.
    public var league: String
    /// When the card starts.
    public var startDate: Date

    public init(
        eventName: String,
        redName: String,
        blueName: String,
        round: Int? = nil,
        clock: String? = nil,
        boutName: String = "",
        status: FightStatus = .upcoming,
        winner: FightCorner? = nil,
        method: String? = nil,
        sourceID: String? = nil,
        league: String = SportLeague.ufc.path,
        startDate: Date = .now
    ) {
        self.eventName = String(eventName.prefix(60))
        self.redName = String(redName.prefix(40))
        self.blueName = String(blueName.prefix(40))
        self.round = round.map { max(1, $0) }
        self.clock = clock
        self.boutName = String(boutName.prefix(40))
        self.status = status
        self.winner = winner
        self.method = method.map { String($0.prefix(24)) }
        self.sourceID = sourceID
        self.league = league
        self.startDate = startDate
    }

    /// The same card with the focused bout's live state refreshed from the feed.
    public func updatingBout(
        redName: String, blueName: String, round: Int?, clock: String?,
        boutName: String, status: FightStatus, winner: FightCorner?, method: String?
    ) -> FightPayload {
        FightPayload(
            eventName: eventName, redName: redName, blueName: blueName,
            round: round, clock: clock, boutName: boutName, status: status,
            winner: winner, method: method,
            sourceID: sourceID, league: league, startDate: startDate)
    }

    // MARK: Display

    public var isLive: Bool { status == .live }

    /// Last word of a fighter's name — what the compact island shows.
    public static func lastName(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }
    public var redLast: String { FightPayload.lastName(redName) }
    public var blueLast: String { FightPayload.lastName(blueName) }

    /// "R2 3:24" while live — the glanceable round/clock.
    public var roundClock: String? {
        guard status == .live, let round else { return nil }
        return clock.map { "R\(round) \($0)" } ?? "R\(round)"
    }

    /// The line under the fighters: round+clock live, start time upcoming, or
    /// the result once decided.
    public func statusLine(now: Date = .now) -> String {
        switch status {
        case .live:
            return roundClock ?? "LIVE"
        case .upcoming:
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: startDate)
        case .finished:
            if let winner {
                let who = winner == .red ? redLast : blueLast
                return method.map { "\(who) · \($0)" } ?? "\(who) wins"
            }
            return "Final"
        }
    }
}

/// A purely decorative pin: no functional content, just a presence in the
/// Dynamic Island wearing the house style. The glyph and accent come from the
/// pin's `PinAppearance`; this payload only carries an optional caption.
public struct DecorPayload: Codable, Hashable, Sendable {
    /// A short caption beside the glyph ("On air", a word, an emoji). Empty or
    /// nil renders the glyph alone.
    public var label: String?
    /// An optional second SF Symbol drawn on the *trailing* side of the Dynamic
    /// Island, so a decoration can frame the island with a glyph on either side
    /// (the leading glyph comes from the pin's `appearance.symbolName`). When
    /// set it takes the compact-trailing slot ahead of the caption.
    public var trailingSymbol: String?

    public init(label: String? = nil, trailingSymbol: String? = nil) {
        self.label = label.map { String($0.prefix(40)) }
        self.trailingSymbol = trailingSymbol.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The caption when there's one worth drawing.
    public var displayLabel: String? {
        guard let label, !label.isEmpty else { return nil }
        return label
    }
}

/// Which market a tracked quote trades on — the one axis that splits a ticker's
/// two upstreams and its trading-hours model. Stocks trade a session with
/// pre/after windows and a weekend close; crypto trades 24/7, so it's always
/// "open".
public enum TickerMarket: String, Codable, Hashable, Sendable, CaseIterable {
    case stock
    case crypto

    /// The picker label.
    public var label: String { self == .stock ? "Stock" : "Crypto" }
    /// The mode's default SF Symbol.
    public var symbol: String { self == .stock ? "chart.line.uptrend.xyaxis" : "bitcoinsign.circle" }
    /// Crypto never closes; a stock's session does.
    public var tradesAroundTheClock: Bool { self == .crypto }
}

/// Where a market is in its trading day, mapped server-side from the quote
/// feed's session flags onto glanceable buckets. Crypto is always `.open`.
public enum MarketState: String, Codable, Hashable, Sendable {
    /// Regular session — the price is live, no tag drawn.
    case open
    /// Before the opening bell — extended-hours price.
    case preMarket
    /// After the closing bell — extended-hours price.
    case afterHours
    /// Market shut (overnight, weekend, holiday) — last close held.
    case closed

    /// The short chip shown beside the price, or nil during the regular
    /// session (when no tag is worth the space).
    public var tag: String? {
        switch self {
        case .open:       nil
        case .preMarket:  "PRE"
        case .afterHours: "AFTER"
        case .closed:     "CLOSED"
        }
    }
}

/// A tracked market quote pinned to the Dynamic Island: one symbol, its live
/// price, the day's change (absolute + percent) and a small intraday sparkline.
/// Price and change refresh via Live Activity updates pushed from the server
/// (see `ActivityPushContract`), so a move lands in the island with Cling
/// closed.
///
/// The symbol travels as its ticker (`AAPL`, `BTC`); the `market` picks the
/// quote feed and the trading-hours model. Numbers come pre-computed from the
/// feed — the renderer never recomputes change from price, so a feed that quotes
/// an extended-hours move stays consistent with its own percentage.
///
/// Light by design: the sparkline is clamped so the encoded payload stays well
/// under the roster's 4KB push budget alongside other pins.
public struct TickerPayload: Codable, Hashable, Sendable {
    /// The ticker the user tracks, upper-cased ("AAPL", "BTC", "TSLA").
    public var symbol: String
    /// Stock or crypto — selects the feed and the hours model.
    public var market: TickerMarket
    /// Full name from the feed ("Apple Inc.", "Bitcoin"); empty until resolved.
    public var name: String
    /// ISO currency the price is quoted in ("USD", "EUR") — drives the symbol
    /// the renderer prefixes.
    public var currency: String

    // Live numbers — filled/refreshed by the feed.

    /// Last traded price.
    public var price: Double
    /// Absolute day change in `currency` (price − previous close); feed-provided
    /// so an extended-hours quote stays self-consistent.
    public var change: Double
    /// Day change as a percent (+0.72 means +0.72%).
    public var changePercent: Double
    /// Session high / low, when the feed gives them — the expanded island's
    /// detail line. nil before the first quote.
    public var dayHigh: Double?
    public var dayLow: Double?
    /// Intraday closes for the sparkline, oldest → newest. Clamped to keep the
    /// payload small; empty before the first quote (the renderer omits the line).
    public var spark: [Double]
    /// Where the market is in its day — drives the PRE/AFTER/CLOSED chip.
    public var state: MarketState

    /// Feed key the poller/Worker reconcile against: "stock:AAPL" / "crypto:BTC".
    public var sourceID: String?
    /// When the feed last refreshed these numbers.
    public var updatedAt: Date?

    /// The most sparkline points worth carrying — a day of half-hourly closes is
    /// ~13; this caps a minute-resolution feed so the push stays small.
    public static let maxSparkPoints = 48

    public init(
        symbol: String,
        market: TickerMarket,
        name: String = "",
        currency: String = "USD",
        price: Double = 0,
        change: Double = 0,
        changePercent: Double = 0,
        dayHigh: Double? = nil,
        dayLow: Double? = nil,
        spark: [Double] = [],
        state: MarketState = .closed,
        sourceID: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.symbol = TickerPayload.normalizeSymbol(symbol)
        self.market = market
        self.name = String(name.prefix(40))
        self.currency = String(currency.uppercased().prefix(4))
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.dayHigh = dayHigh
        self.dayLow = dayLow
        self.spark = Array(spark.suffix(TickerPayload.maxSparkPoints))
        self.state = state
        self.sourceID = sourceID
        self.updatedAt = updatedAt
    }

    /// The same quote with fresh numbers from the feed — keeps the user's
    /// symbol/market/identity, swaps what the market moved.
    public func updating(
        name: String? = nil,
        currency: String? = nil,
        price: Double,
        change: Double,
        changePercent: Double,
        dayHigh: Double?? = nil,
        dayLow: Double?? = nil,
        spark: [Double]? = nil,
        state: MarketState,
        updatedAt: Date
    ) -> TickerPayload {
        TickerPayload(
            symbol: symbol,
            market: market,
            name: name ?? self.name,
            currency: currency ?? self.currency,
            price: price,
            change: change,
            changePercent: changePercent,
            dayHigh: dayHigh ?? self.dayHigh,
            dayLow: dayLow ?? self.dayLow,
            spark: spark ?? self.spark,
            state: state,
            sourceID: sourceID,
            updatedAt: updatedAt)
    }

    /// Symbols are upper-cased and stripped to letters/digits (and the dot some
    /// tickers carry, "BRK.B") so the renderer and feed key get a clean value.
    static func normalizeSymbol(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "." }.prefix(10))
    }

    /// The feed key for a symbol+market: "stock:AAPL".
    public static func makeSourceID(market: TickerMarket, symbol: String) -> String {
        "\(market.rawValue):\(normalizeSymbol(symbol))"
    }

    // Forward-compatible: only `symbol` and `market` are truly required;
    // everything else defaults so a pin stored before a field existed still
    // decodes.
    private enum CodingKeys: String, CodingKey {
        case symbol, market, name, currency
        case price, change, changePercent, dayHigh, dayLow, spark, state
        case sourceID, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? ""
        market = (try? c.decode(TickerMarket.self, forKey: .market)) ?? .stock
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "USD"
        price = (try? c.decode(Double.self, forKey: .price)) ?? 0
        change = (try? c.decode(Double.self, forKey: .change)) ?? 0
        changePercent = (try? c.decode(Double.self, forKey: .changePercent)) ?? 0
        dayHigh = try? c.decodeIfPresent(Double.self, forKey: .dayHigh)
        dayLow = try? c.decodeIfPresent(Double.self, forKey: .dayLow)
        spark = (try? c.decode([Double].self, forKey: .spark)) ?? []
        state = (try? c.decode(MarketState.self, forKey: .state)) ?? .closed
        sourceID = try? c.decodeIfPresent(String.self, forKey: .sourceID)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    // MARK: Display

    /// Whether the day's move is flat-or-up — drives the green/red split and the
    /// arrow direction. (Zero counts as up, drawn neutral-green by convention.)
    public var isUp: Bool { change >= 0 }

    /// A triangle pointing the way the price moved.
    public var arrow: String { isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill" }

    /// The currency symbol for the quote's currency — "$", "€", "£", else the code.
    public var currencySymbol: String {
        switch currency {
        case "USD": "$"
        case "EUR": "€"
        case "GBP": "£"
        case "JPY": "¥"
        default:    ""
        }
    }

    /// Sensible decimal places: crypto under $1 wants more (a sub-cent coin),
    /// everything else reads in two.
    private var decimals: Int {
        if market == .crypto && price > 0 && price < 1 { return 6 }
        return 2
    }

    private func money(_ value: Double) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.minimumFractionDigits = decimals
        n.maximumFractionDigits = decimals
        let body = n.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        let sym = currencySymbol
        return sym.isEmpty ? "\(body) \(currency)" : "\(sym)\(body)"
    }

    /// The headline price, currency-prefixed: "$229.35".
    public var priceText: String { money(price) }

    /// The absolute change with an explicit sign: "+1.62" / "−0.84".
    public var changeText: String {
        let sign = isUp ? "+" : "−"
        return "\(sign)\(money(abs(change)))"
    }

    /// The percent change with sign: "+0.72%" / "−1.40%".
    public var changePercentText: String {
        let sign = isUp ? "+" : "−"
        return String(format: "%@%.2f%%", sign, abs(changePercent))
    }

    /// The compact-island trailing glance: "+0.72%".
    public var compactChange: String { changePercentText }

    /// "AAPL · Apple Inc." (or just the symbol when the name hasn't resolved) —
    /// the list-row and lock-screen title.
    public var titleLine: String {
        name.isEmpty ? symbol : "\(symbol) · \(name)"
    }

    /// The PRE/AFTER/CLOSED chip, suppressed for always-on crypto during a move.
    public var stateTag: String? {
        if market == .crypto && state == .open { return nil }
        return state.tag
    }
}

// MARK: - Per-type payloads

public struct NotePayload: Codable, Hashable, Sendable {
    /// Glanceable text — anything you want held in view, including pasted
    /// snippets. Clamped well under the ContentState budget.
    public var text: String
    /// Optional photo (a shared image, a whiteboard snap) in `PhotoStore`'s
    /// App Group directory — filename only, never bytes.
    public var photoFilename: String?
    /// Where the text came from, when shared from a web page — provenance for
    /// notes pinned via the share sheet.
    public var sourceURL: URL?

    public init(text: String, photoFilename: String? = nil, sourceURL: URL? = nil) {
        self.text = String(text.prefix(1000))
        self.photoFilename = photoFilename
        self.sourceURL = sourceURL
    }
}

/// How a timer pin draws its countdown on the lock-screen card (and, where it
/// fits, the expanded island). The numbers always tick client-side via
/// `Text(timerInterval:)`/`ProgressView(timerInterval:)`; this only picks the
/// shape wrapped around them.
public enum CountdownStyle: String, Codable, Sendable, Hashable, CaseIterable {
    /// Just the numerals — the quietest, most glanceable.
    case text
    /// Numerals beside a circular progress ring that empties as time runs out.
    case ring
    /// Numerals over a thin horizontal bar that drains left-to-right.
    case bar
    /// Numerals over the whole card, its accent fill receding as time runs out.
    case fill

    public var label: String {
        switch self {
        case .text: "Text"
        case .ring: "Ring"
        case .bar:  "Bar"
        case .fill: "Fill"
        }
    }
}

public struct TimerPayload: Codable, Hashable, Sendable {
    /// What the countdown is for ("Pasta", "Rest", "Meeting").
    public var label: String
    /// When the countdown started — kept so progress reads true after a
    /// relaunch or re-arm rather than resetting visually.
    public var startDate: Date
    /// The moment the countdown hits zero.
    public var endDate: Date
    /// How the countdown renders. Per-pin so different timers can read
    /// differently (a ring for a workout, plain text for a meeting).
    public var style: CountdownStyle

    public init(label: String, startDate: Date = .now, endDate: Date, style: CountdownStyle = .text) {
        self.label = String(label.prefix(100))
        self.startDate = startDate
        self.endDate = endDate
        self.style = style
    }

    // Forward-compatible decoding: pins stored before `style` existed lack the
    // key, so fall back to `.text` rather than failing the whole store.
    private enum CodingKeys: String, CodingKey {
        case label, startDate, endDate, style
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        style = (try? c.decode(CountdownStyle.self, forKey: .style)) ?? .text
    }
}

public struct ParkingPayload: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// The headline on the activity — defaults to "Parked here" when nil, but
    /// it's the user's pin: "Train", "Bike's locked up", whatever.
    public var title: String?
    /// "Level 3, row F" — the detail GPS can't give you.
    public var note: String?
    /// Filename of a photo in `PhotoStore`'s App Group directory. A name, not
    /// bytes — the widget process shares the container and loads it itself.
    public var photoFilename: String?

    public init(
        latitude: Double,
        longitude: Double,
        title: String? = nil,
        note: String? = nil,
        photoFilename: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.title = title.map { String($0.prefix(100)) }
        self.note = note.map { String($0.prefix(200)) }
        self.photoFilename = photoFilename
    }

    /// What the renderers show — the user's title, or the default.
    public var displayTitle: String { title ?? "Parked here" }

    /// Walking directions to the spot, in the user's chosen maps app. Built
    /// here (not async) so the widget process can hand straight off to Maps.
    public func walkingDirectionsURL(provider: MapProvider) -> URL {
        provider.walkingDirectionsURL(latitude: latitude, longitude: longitude)
    }
}
