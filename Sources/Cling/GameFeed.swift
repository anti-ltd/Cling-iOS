/**
 `GameFeed`: the US-league score source. Reads ESPN's public scoreboard for any
 of the team leagues (`basketball/nba`, `football/nfl`, `hockey/nhl`,
 `baseball/mlb`) — no key, no auth — and maps each game onto a `TeamGamePayload`
 the rest of the app already knows how to pin and render.

 Twin of `MatchFeed`/`FightFeed`, generic over the league path: the period model
 differs per sport (quarters / periods / innings), so the caller's `SportLeague`
 supplies the `GameSport`. The decode here is the reference the push Worker
 mirrors server-side.
 */
import Foundation

enum GameFeed {
    /// Fetch the current games for one league. Throws on transport/decode
    /// failure so the browser can show a retry rather than a silent empty list.
    static func fetch(leaguePath: String, now: Date = .now) async throws -> [TeamGamePayload] {
        guard let league = SportLeague.allCases.first(where: { $0.path == leaguePath }),
              let sport = league.gameSport else { return [] }
        var req = URLRequest(url: ESPNScoreboard.url(leaguePath: leaguePath))
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let board = try JSONDecoder().decode(Scoreboard.self, from: data)
        return board.events.compactMap { $0.payload(sport: sport, league: league) }
    }
}

// MARK: - ESPN team scoreboard shape (only the fields we use)

private struct Scoreboard: Decodable {
    let events: [Event]
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
        let displayClock: String?
        let period: Int?
        let type: StatusType
    }
    struct StatusType: Decodable {
        let state: String?        // "pre" | "in" | "post"
        let shortDetail: String?  // "Q3 5:21", "Halftime", "Top 5th", "Final"
        let completed: Bool?
    }
    struct Competitor: Decodable {
        let homeAway: String?
        let score: String?
        let team: Team
        struct Team: Decodable { let abbreviation: String? }
    }

    /// Collapse one ESPN event onto a `TeamGamePayload`. Returns nil if it lacks
    /// the home/away pair we need to render a score.
    func payload(sport: GameSport, league: SportLeague) -> TeamGamePayload? {
        guard let comp = competitions.first,
              let home = comp.competitors.first(where: { $0.homeAway == "home" }),
              let away = comp.competitors.first(where: { $0.homeAway == "away" }),
              let homeAbbr = home.team.abbreviation,
              let awayAbbr = away.team.abbreviation
        else { return nil }

        let status = Self.mapStatus(comp.status)
        let live = status == .live
        return TeamGamePayload(
            sport: sport,
            league: league.path,
            leagueName: league.label,
            homeAbbr: homeAbbr,
            awayAbbr: awayAbbr,
            homeScore: Int(home.score ?? "0") ?? 0,
            awayScore: Int(away.score ?? "0") ?? 0,
            period: live ? comp.status.period : nil,
            // Baseball has no running clock; the situation line ("Top 5th")
            // carries the half-inning instead.
            clock: (live && sport.hasClock) ? comp.status.displayClock : nil,
            situation: (live && sport == .baseball) ? comp.status.type.shortDetail : nil,
            status: status,
            startTime: ESPNScoreboard.parseDate(date) ?? .now,
            sourceID: id)
    }

    private static func mapStatus(_ s: Status) -> GameStatus {
        // Halftime reports state "in" with shortDetail "Halftime" — split it out
        // so the island shows the break rather than a stale clock.
        if (s.type.shortDetail ?? "").lowercased().contains("half") { return .halftime }
        switch s.type.state {
        case "pre":  return .scheduled
        case "in":   return .live
        case "post": return .finished
        default:     return (s.type.completed == true) ? .finished : .scheduled
        }
    }
}
