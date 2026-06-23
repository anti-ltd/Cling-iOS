/**
 `TeamFormFeed`: a team's recent results, read from ESPN's team-schedule
 endpoint (`…/teams/<abbr>/schedule`). Twin of `GameFeed`, but where `GameFeed`
 powers the live pin, this is in-app only — it fills the pin detail screen's
 "Recent form" with the last few finished games for each side of a tracked game.

 Keyed off `SportLeague.path` + the league abbreviation the scoreboard already
 carries (`LAL`, `BOS`), so it needs nothing the pin doesn't already hold and
 never touches the push payload.
 */
import Foundation

/// Win / draw / loss — soccer can tie, the US leagues can't, so the same model
/// carries all three.
enum Outcome: String, Sendable { case win = "W", draw = "D", loss = "L" }

/// One finished game from a team's schedule, framed from that team's side: who
/// they played, where, the score, and how it went.
struct TeamResult: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date
    let opponentAbbr: String
    let home: Bool
    let teamScore: Int
    let oppScore: Int
    let outcome: Outcome

    /// "W 110–98" / "D 1–1" / "L 107–125".
    var scoreLine: String { "\(outcome.rawValue) \(teamScore)–\(oppScore)" }
    /// "vs BOS" at home, "@ BOS" away.
    var matchup: String { (home ? "vs " : "@ ") + opponentAbbr }
}

enum TeamFormFeed {
    /// The team's most recent finished games, newest first. Throws on
    /// transport/decode failure so the detail view can hide the section rather
    /// than show a half-loaded mess.
    static func recent(leaguePath: String, teamAbbr: String, limit: Int = 5, now: Date = .now) async throws -> [TeamResult] {
        let abbr = teamAbbr.uppercased()
        guard !abbr.isEmpty else { return [] }
        var req = URLRequest(url: ESPNScoreboard.scheduleURL(leaguePath: leaguePath, team: abbr))
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let schedule = try JSONDecoder().decode(Schedule.self, from: data)
        return schedule.events
            .compactMap { $0.result(for: abbr) }
            .filter { $0.date <= now }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - ESPN team-schedule shape (only the fields we use)

private struct Schedule: Decodable {
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
        let type: StatusType
    }
    struct StatusType: Decodable {
        let completed: Bool?
    }
    struct Competitor: Decodable {
        let homeAway: String?
        let winner: Bool?
        let score: Score?
        let team: Team
        struct Team: Decodable { let abbreviation: String? }
    }

    /// Reframe one schedule event from `abbr`'s side. nil unless it's a finished
    /// game with both sides resolved.
    func result(for abbr: String) -> TeamResult? {
        guard let comp = competitions.first,
              comp.status.type.completed == true,
              let mine = comp.competitors.first(where: { $0.team.abbreviation?.uppercased() == abbr }),
              let opp = comp.competitors.first(where: { $0.team.abbreviation?.uppercased() != abbr }),
              let oppAbbr = opp.team.abbreviation,
              let when = ESPNScoreboard.parseDate(date)
        else { return nil }
        let mineScore = mine.score?.points ?? 0
        let oppScore = opp.score?.points ?? 0
        let outcome: Outcome
        if mineScore == oppScore {
            outcome = .draw
        } else {
            // Trust ESPN's winner flag; fall back to the scores for a tie-break.
            outcome = (mine.winner ?? (mineScore > oppScore)) ? .win : .loss
        }
        return TeamResult(
            id: id,
            date: when,
            opponentAbbr: oppAbbr,
            home: mine.homeAway == "home",
            teamScore: mineScore,
            oppScore: oppScore,
            outcome: outcome)
    }
}

/// ESPN reports a competitor's score as an object on the schedule endpoint
/// (`{ value: 110, displayValue: "110" }`) but as a bare string on the
/// scoreboard — decode either so one model serves both shapes.
private struct Score: Decodable {
    let points: Int

    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            points = Int(Double(s) ?? 0)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Double.self, forKey: .value) { points = Int(v); return }
        if let dv = try? c.decode(String.self, forKey: .displayValue) { points = Int(Double(dv) ?? 0); return }
        points = 0
    }

    enum CodingKeys: String, CodingKey { case value, displayValue }
}
