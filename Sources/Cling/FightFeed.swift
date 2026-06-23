/**
 `FightFeed`: the UFC source. Reads ESPN's public MMA scoreboard
 (`mma/ufc/scoreboard`) and maps each event **card** onto a `FightPayload` whose
 focused bout is whatever's most relevant — the bout in progress, else the main
 event (before the card, or with its result after).

 Twin of `MatchFeed`, different sport. The card→payload mapping here is the
 reference the push Worker mirrors server-side.
 */
import Foundation

enum FightFeed {
    static func fetch() async throws -> [FightPayload] {
        var req = URLRequest(url: ESPNScoreboard.url(leaguePath: SportLeague.ufc.path))
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let board = try JSONDecoder().decode(Scoreboard.self, from: data)
        return board.events.compactMap { $0.payload() }
    }
}

// MARK: - ESPN MMA scoreboard shape (only the fields we use)

private struct Scoreboard: Decodable {
    let events: [Event]
}

private struct Event: Decodable {
    let id: String
    let name: String?
    let date: String?
    let competitions: [Bout]

    /// Collapse a card onto its focused bout.
    func payload() -> FightPayload? {
        guard !competitions.isEmpty else { return nil }

        let cardStatus: FightStatus = {
            if competitions.allSatisfy({ $0.state == "post" }) { return .finished }
            // Any bout in progress OR already finished means the card is underway
            // (we're mid-card, between or during bouts).
            if competitions.contains(where: { $0.state == "in" || $0.state == "post" }) { return .live }
            return .upcoming
        }()

        guard let bout = focusedBout(cardStatus: cardStatus),
              let red = bout.competitors?.first,
              let blue = bout.competitors?.dropFirst().first,
              let redName = red.athlete?.displayName,
              let blueName = blue.athlete?.displayName
        else { return nil }

        let live = bout.state == "in"
        let decided = bout.state == "post"
        let winner: FightCorner? = decided
            ? (red.winner == true ? .red : (blue.winner == true ? .blue : nil))
            : nil

        return FightPayload(
            eventName: name ?? "UFC",
            redName: redName,
            blueName: blueName,
            round: live ? bout.status?.period : nil,
            clock: live ? bout.status?.displayClock : nil,
            boutName: boutLabel(bout),
            status: cardStatus,
            winner: winner,
            method: decided ? bout.method : nil,
            sourceID: id,
            league: SportLeague.ufc.path,
            startDate: ESPNScoreboard.parseDate(date) ?? .now)
    }

    /// The bout to show, so the pin follows the action:
    /// - while the card is underway: the bout in progress, else the next one up;
    /// - before it starts / after it ends: the main event (the headline, with
    ///   its result once decided).
    private func focusedBout(cardStatus: FightStatus) -> Bout? {
        switch cardStatus {
        case .live:
            return competitions.first(where: { $0.state == "in" })
                ?? competitions.first(where: { $0.state == "pre" })
                ?? mainEventBout ?? competitions.last
        case .upcoming, .finished:
            return mainEventBout ?? competitions.last
        }
    }

    /// The bout whose fighters name the card ("Kape vs. Horiguchi").
    private var mainEventBout: Bout? {
        let title = (name ?? "").lowercased()
        return competitions.first { bout in
            guard let cs = bout.competitors, cs.count >= 2,
                  let a = cs[0].athlete?.lastName, let b = cs[1].athlete?.lastName
            else { return false }
            return title.contains(a.lowercased()) && title.contains(b.lowercased())
        }
    }

    private func boutLabel(_ bout: Bout) -> String {
        // The card-naming bout is the main event; otherwise the weight class.
        let title = (name ?? "").lowercased()
        if let cs = bout.competitors, cs.count >= 2,
           let a = cs[0].athlete?.lastName, let b = cs[1].athlete?.lastName,
           title.contains(a.lowercased()), title.contains(b.lowercased()) {
            return "Main Event"
        }
        return bout.type?.abbreviation ?? ""
    }
}

private struct Bout: Decodable {
    let status: Status?
    let competitors: [Competitor]?
    let type: BoutType?
    let details: [Detail]?

    var state: String? { status?.type?.state }

    /// Method of victory, distilled from ESPN's free-text result rows.
    var method: String? {
        let texts = (details ?? []).compactMap { $0.type?.text?.lowercased() }
        if texts.contains(where: { $0.contains("submission") }) { return "Submission" }
        if texts.contains(where: { $0.contains("ko") || $0.contains("knockout") }) { return "KO/TKO" }
        if texts.contains(where: { $0.contains("decision") }) { return "Decision" }
        return nil
    }

    struct Status: Decodable {
        let period: Int?
        let displayClock: String?
        let type: StatusType?
    }
    struct StatusType: Decodable {
        let state: String?
        let completed: Bool?
    }
    struct Competitor: Decodable {
        let winner: Bool?
        let athlete: Athlete?
    }
    struct Athlete: Decodable {
        let displayName: String?
        var lastName: String? {
            displayName?.split(separator: " ").last.map(String.init)
        }
    }
    struct BoutType: Decodable { let abbreviation: String? }
    struct Detail: Decodable { let type: DetailType? }
    struct DetailType: Decodable { let text: String? }
}
