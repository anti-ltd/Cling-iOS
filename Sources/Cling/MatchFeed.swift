/**
 `MatchFeed`: the World Cup score source. Reads ESPN's public scoreboard
 (`site.api.espn.com/.../soccer/fifa.world/scoreboard`) — no key, no auth — and
 maps each fixture onto a `MatchPayload` the rest of the app already knows how
 to pin and render.

 Two callers:
 - the match browser, to list what's on and let you pin one;
 - the foreground live updater (`AppModel.refreshLiveMatches`), to pull fresh
   scores while Cling is open.

 When Cling is closed the island is kept live by the push server (Phase 3),
 which polls this same feed server-side. The decode here is the reference for
 the field mapping either side uses.
 */
import Foundation

enum MatchFeed {
    static let scoreboardURL = URL(string:
        "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard")!

    /// Fetch the current World Cup fixtures, newest-relevant first (live, then
    /// upcoming, then finished). Throws on transport/decode failure so the
    /// browser can show a retry rather than a silent empty list.
    static func fetch(now: Date = .now) async throws -> [MatchPayload] {
        var req = URLRequest(url: scoreboardURL)
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let board = try JSONDecoder().decode(Scoreboard.self, from: data)
        return board.events.compactMap { $0.payload(competition: board.competitionName) }
    }
}

// MARK: - Commentary (in-app play-by-play history)

/// One play-by-play line from a match's commentary feed, framed for the detail
/// screen's timeline: the minute it happened, the text, and a coarse kind that
/// picks the row's icon/tint.
struct CommentaryEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case goal, card, substitution, penalty, whistle, other }
    /// ESPN's sequence number — stable and ordered.
    let id: Int
    /// "67'", "90'+2'", or "" for pre/post-match lines.
    let minute: String
    let text: String
    let kind: Kind

    /// Map ESPN's play-type slug onto a coarse kind for the row icon, falling
    /// back to a light text sniff (some lines are only tagged in prose).
    static func kind(slug: String?, text: String) -> Kind {
        switch slug?.lowercased() {
        case "goal", "own-goal", "penalty-goal":            return .goal
        case "yellow-card", "red-card", "yellow-red-card":  return .card
        case "substitution":                                return .substitution
        case "penalty", "penalty-missed", "penalty-saved":  return .penalty
        default:
            let t = text.lowercased()
            if t.hasPrefix("goal!") { return .goal }
            if t.contains("half ends") || t.hasPrefix("match ends") || t.hasPrefix("kick-off") { return .whistle }
            return .other
        }
    }
}

/// A match's full play-by-play, newest first. In-app only — the Live Activity
/// carries just the latest line (4KB push budget), but the detail screen can
/// pull the whole `commentary[]` from ESPN's per-event summary (the same
/// endpoint the push server reads). Twin of `MatchFeed.fetch`.
enum MatchCommentary {
    static func fetch(leaguePath: String, eventID: String, limit: Int = 50) async throws -> [CommentaryEntry] {
        guard !eventID.isEmpty else { return [] }
        var req = URLRequest(url: ESPNScoreboard.summaryURL(leaguePath: leaguePath, event: eventID))
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let summary = try JSONDecoder().decode(Summary.self, from: data)
        // ESPN lists oldest→newest; reverse for a newest-first timeline.
        return (summary.commentary ?? []).reversed().compactMap { $0.entry }.prefix(limit).map { $0 }
    }

    private struct Summary: Decodable { let commentary: [Item]? }

    private struct Item: Decodable {
        let sequence: Int?
        let text: String?
        let time: Time?
        let play: Play?
        struct Time: Decodable { let displayValue: String? }
        struct Play: Decodable {
            let type: PlayType?
            struct PlayType: Decodable { let type: String? }
        }

        var entry: CommentaryEntry? {
            guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  let seq = sequence
            else { return nil }
            return CommentaryEntry(
                id: seq,
                minute: time?.displayValue ?? "",
                text: raw,
                kind: CommentaryEntry.kind(slug: play?.type?.type, text: raw))
        }
    }
}

// MARK: - ESPN scoreboard shape (only the fields we use)

private struct Scoreboard: Decodable {
    let leagues: [League]?
    let events: [Event]

    var competitionName: String { leagues?.first?.name ?? "World Cup" }

    struct League: Decodable { let name: String? }
}

private struct Event: Decodable {
    let id: String
    let date: String?
    let competitions: [Competition]

    struct Competition: Decodable {
        let status: Status
        let competitors: [Competitor]
    }
    struct Status: Decodable {
        let clock: Double?
        let displayClock: String?
        let type: StatusType
    }
    struct StatusType: Decodable {
        let name: String?         // "STATUS_IN_PROGRESS", "STATUS_SUSPENDED", …
        let state: String?        // "pre" | "in" | "post"
        let shortDetail: String?  // "16'", "HT", "FT"
        let completed: Bool?
    }
    struct Competitor: Decodable {
        let homeAway: String?
        let score: String?
        let team: Team
        struct Team: Decodable {
            let abbreviation: String?
            let displayName: String?
        }
    }

    /// Collapse one ESPN event onto a `MatchPayload`. Returns nil if it lacks
    /// the home/away pair we need to render a score.
    func payload(competition: String) -> MatchPayload? {
        guard let comp = competitions.first,
              let home = comp.competitors.first(where: { $0.homeAway == "home" }),
              let away = comp.competitors.first(where: { $0.homeAway == "away" }),
              let homeCode = home.team.abbreviation,
              let awayCode = away.team.abbreviation
        else { return nil }

        let status = Self.mapStatus(comp.status)
        let minute = status == .live ? Self.minute(from: comp.status) : nil

        return MatchPayload(
            homeCode: homeCode,
            awayCode: awayCode,
            homeName: home.team.displayName ?? "",
            awayName: away.team.displayName ?? "",
            homeScore: Int(home.score ?? "0") ?? 0,
            awayScore: Int(away.score ?? "0") ?? 0,
            minute: minute,
            status: status,
            competition: competition,
            kickoff: ESPNScoreboard.parseDate(date) ?? .now,
            sourceID: id)
    }

    private static func mapStatus(_ s: Status) -> MatchStatus {
        // A suspended/abandoned match still reports state "in", so without this
        // it'd map to .live and freeze on a stale minute. The feed's type name
        // is the only signal that play has stopped.
        switch s.type.name {
        case "STATUS_SUSPENDED", "STATUS_ABANDONED", "STATUS_DELAYED":
            return .suspended
        default:
            break
        }
        // Halftime reports state "in" with shortDetail "HT" — split it out so
        // the island shows the break rather than a stale minute.
        if (s.type.shortDetail ?? "").uppercased().hasPrefix("HT") { return .halftime }
        switch s.type.state {
        case "pre":  return .scheduled
        case "in":   return .live
        case "post": return .finished
        default:     return (s.type.completed == true) ? .finished : .scheduled
        }
    }

    /// ESPN's `clock` is seconds elapsed (960 → 16'); fall back to parsing the
    /// leading number out of `displayClock` ("90'+5'" → 90).
    private static func minute(from s: Status) -> Int? {
        if let secs = s.clock, secs > 0 { return Int(secs / 60) }
        let digits = (s.displayClock ?? "").prefix { $0.isNumber }
        return Int(digits)
    }
}
