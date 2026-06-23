/**
 The one place a sport's ESPN scoreboard URL is built. Every live-sports feed
 (`MatchFeed`, `FightFeed`) and the sport-agnostic plumbing key off a
 `SportLeague.path` (`soccer/fifa.world`, `mma/ufc`), so adding a sport never
 touches URL construction.
 */
import Foundation

enum ESPNScoreboard {
    /// `https://site.api.espn.com/apis/site/v2/sports/<leaguePath>/scoreboard`.
    static func url(leaguePath: String) -> URL {
        URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(leaguePath)/scoreboard")!
    }

    /// One team's season schedule (past + upcoming) — the source for recent
    /// form. `…/teams/<team>/schedule`; the team segment takes the same league
    /// abbreviation the scoreboard hands us (`LAL`, `BOS`).
    static func scheduleURL(leaguePath: String, team: String) -> URL {
        URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(leaguePath)/teams/\(team)/schedule")!
    }

    /// One event's full detail (lineups, stats, play-by-play) — the source for
    /// the in-app commentary timeline. `…/summary?event=<id>`. The same endpoint
    /// the push server reads for the latest-line enrichment.
    static func summaryURL(leaguePath: String, event: String) -> URL {
        URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(leaguePath)/summary?event=\(event)")!
    }

    /// Parse an ESPN event-`date`. ESPN emits minute-precision ISO8601 with no
    /// seconds ("2026-06-21T17:00Z"), which `.withInternetDateTime` (the default)
    /// rejects because it requires seconds — so a bare formatter returns nil and
    /// every kickoff falls back to "now". Try the seconds-required form first,
    /// then the seconds-optional fallback.
    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return isoWithSeconds.date(from: s) ?? isoNoSeconds.date(from: s)
    }

    // These are only ever read (parsing), never reconfigured, so the unchecked
    // annotation is safe. ISO8601DateFormatter handles the seconds-bearing form;
    // every ISO8601DateFormatter time option requires seconds, so the
    // minute-precision form ESPN actually sends needs an explicit DateFormatter.
    nonisolated(unsafe) private static let isoWithSeconds = ISO8601DateFormatter()
    nonisolated(unsafe) private static let isoNoSeconds: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"   // 2026-06-21T17:00Z
        return f
    }()
}
