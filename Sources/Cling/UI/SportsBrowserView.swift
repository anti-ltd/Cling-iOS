/**
 The live-sports browser: pick a sport, see what's on (live from ESPN), tap to
 drop it into the Dynamic Island. A football match or a UFC card — the sport
 switcher just swaps which feed loads and which rows render; pinning routes to
 `pinMatch` / `pinFight` / `pinGame`. Adding a sport here is one `SportLeague`
 case plus a row view.

 `LiveSportsList` holds all of it minus chrome, so it serves both as a pushed
 step inside the pin builder (the one true creation funnel) and as a standalone
 sheet. Pinning here always picks a *real* fixture — one with a feed `sourceID`
 the push server can keep current — which is exactly why live pins must be made
 here and never hand-typed.
 */
import SwiftUI
import iUXiOS

/// Standalone sheet wrapper — its own navigation + Done. Kept thin; the work
/// lives in `LiveSportsList`.
struct SportsBrowserView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LiveSportsList { dismiss() }
                .navigationTitle("Live Sports")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// The sport switcher + fixture list, chrome-free so it can be pushed into
/// another navigation stack. `onPinned` fires after a fixture is pinned (the
/// caller dismisses or pops).
struct LiveSportsList: View {
    @Environment(AppModel.self) private var model

    /// Called once a fixture has been pinned.
    var onPinned: () -> Void = {}

    @State private var sport: SportLeague = .worldCup
    @State private var matches: [MatchPayload] = []
    @State private var fights: [FightPayload] = []
    @State private var games: [TeamGamePayload] = []
    @State private var phase: LoadPhase = .loading

    private enum LoadPhase: Equatable { case loading, loaded, failed }

    var body: some View {
        VStack(spacing: 0) {
            // A scrolling chip bar rather than a segmented control — it
            // scales to however many leagues we add without cramping.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SportLeague.allCases, id: \.self) { s in
                        let selected = s == sport
                        Button { sport = s } label: {
                            Label(s.label, systemImage: s.systemImage)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 12)
                                .background(
                                    Capsule().fill(selected
                                        ? AnyShapeStyle(.tint)
                                        : AnyShapeStyle(.ultraThinMaterial)))
                                .foregroundStyle(selected
                                    ? AnyShapeStyle(.white)
                                    : AnyShapeStyle(.primary))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, UX.cardSpacing)
            .padding(.bottom, 8)

            content
        }
        .task(id: sport) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading where isEmpty:
            ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed where isEmpty:
            ContentUnavailableView {
                Label("No connection", systemImage: "wifi.slash")
            } description: {
                Text("Couldn't reach the score feed.")
            } actions: {
                Button("Retry") { Task { await load() } }.buttonStyle(.glassBloom)
            }
        default:
            List {
                switch sport {
                case .worldCup:               matchSections
                case .ufc:                    fightSections
                case .nba, .nfl, .nhl, .mlb:  gameSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
    }

    // MARK: Football

    @ViewBuilder private var matchSections: some View {
        if matches.isEmpty {
            Text("No World Cup matches scheduled.").foregroundStyle(.secondary)
        } else {
            section("Live", matches.filter(\.isLive)) { m in MatchRow(match: m, pinned: isMatchPinned(m)) { model.pinMatch(m); onPinned() } }
            section("Upcoming", matches.filter { $0.status == .scheduled }) { m in MatchRow(match: m, pinned: isMatchPinned(m)) { model.pinMatch(m); onPinned() } }
            section("Final", matches.filter { $0.status == .finished }) { m in MatchRow(match: m, pinned: isMatchPinned(m)) { model.pinMatch(m); onPinned() } }
        }
    }

    // MARK: UFC

    @ViewBuilder private var fightSections: some View {
        if fights.isEmpty {
            Text("No UFC cards scheduled.").foregroundStyle(.secondary)
        } else {
            section("Live", fights.filter(\.isLive)) { f in FightRow(fight: f, pinned: isFightPinned(f)) { model.pinFight(f); onPinned() } }
            section("Upcoming", fights.filter { $0.status == .upcoming }) { f in FightRow(fight: f, pinned: isFightPinned(f)) { model.pinFight(f); onPinned() } }
            section("Final", fights.filter { $0.status == .finished }) { f in FightRow(fight: f, pinned: isFightPinned(f)) { model.pinFight(f); onPinned() } }
        }
    }

    // MARK: Team games (NBA / NFL / NHL / MLB)

    @ViewBuilder private var gameSections: some View {
        if games.isEmpty {
            Text("No \(sport.label) games scheduled.").foregroundStyle(.secondary)
        } else {
            section("Live", games.filter(\.isLive)) { g in GameRow(game: g, pinned: isGamePinned(g)) { model.pinGame(g); onPinned() } }
            section("Upcoming", games.filter { $0.status == .scheduled }) { g in GameRow(game: g, pinned: isGamePinned(g)) { model.pinGame(g); onPinned() } }
            section("Final", games.filter { $0.status == .finished }) { g in GameRow(game: g, pinned: isGamePinned(g)) { model.pinGame(g); onPinned() } }
        }
    }

    @ViewBuilder private func section<T, Row: View>(_ title: String, _ items: [T], @ViewBuilder row: @escaping (T) -> Row) -> some View {
        if !items.isEmpty {
            Section(title) { ForEach(Array(items.enumerated()), id: \.offset) { row($0.element) } }
        }
    }

    // MARK: Loading + pinned state

    private var isEmpty: Bool {
        switch sport {
        case .worldCup:              matches.isEmpty
        case .ufc:                   fights.isEmpty
        case .nba, .nfl, .nhl, .mlb: games.isEmpty
        }
    }

    private func isMatchPinned(_ m: MatchPayload) -> Bool {
        guard let id = m.sourceID else { return false }
        return model.pins.contains { if case .match(let p) = $0.payload { return p.sourceID == id }; return false }
    }
    private func isFightPinned(_ f: FightPayload) -> Bool {
        guard let id = f.sourceID else { return false }
        return model.pins.contains { if case .fight(let p) = $0.payload { return p.sourceID == id }; return false }
    }
    private func isGamePinned(_ g: TeamGamePayload) -> Bool {
        guard let id = g.sourceID else { return false }
        return model.pins.contains { if case .game(let p) = $0.payload { return p.sourceID == id }; return false }
    }

    private func load() async {
        if isEmpty { phase = .loading }
        do {
            switch sport {
            case .worldCup:              matches = try await MatchFeed.fetch()
            case .ufc:                   fights = try await FightFeed.fetch()
            case .nba, .nfl, .nhl, .mlb: games = try await GameFeed.fetch(leaguePath: sport.path)
            }
            phase = .loaded
        } catch {
            phase = .failed
        }
    }
}

private struct MatchRow: View {
    let match: MatchPayload
    let pinned: Bool
    let onPin: () -> Void

    var body: some View {
        Button(action: onPin) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    teamLine(code: match.homeCode, name: match.homeLabel, score: match.homeScore)
                    teamLine(code: match.awayCode, name: match.awayLabel, score: match.awayScore)
                }
                Spacer(minLength: 8)
                statusColumn(line: match.statusLine(), phase: LiveStatusDot.phase(for: match.status), pinned: pinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pinned)
    }

    private func teamLine(code: String, name: String, score: Int) -> some View {
        HStack(spacing: 8) {
            FlagImage(code, size: 22)
            Text(name).font(.body.weight(.medium)).lineLimit(1)
            Spacer(minLength: 4)
            if match.status != .scheduled {
                Text("\(score)").font(.body.weight(.bold).monospacedDigit())
            }
        }
    }
}

private struct FightRow: View {
    let fight: FightPayload
    let pinned: Bool
    let onPin: () -> Void

    var body: some View {
        Button(action: onPin) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fight.eventName).font(.body.weight(.semibold)).lineLimit(1)
                    Text("\(fight.redLast) vs \(fight.blueLast)\(fight.boutName.isEmpty ? "" : " · \(fight.boutName)")")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                statusColumn(line: fight.statusLine(), phase: fight.status == .live ? .playing : nil, pinned: pinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pinned)
    }
}

private struct GameRow: View {
    let game: TeamGamePayload
    let pinned: Bool
    let onPin: () -> Void

    var body: some View {
        Button(action: onPin) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    teamLine(abbr: game.homeAbbr, score: game.homeScore)
                    teamLine(abbr: game.awayAbbr, score: game.awayScore)
                }
                Spacer(minLength: 8)
                statusColumn(line: game.statusLine(), phase: LiveStatusDot.phase(for: game.status), pinned: pinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pinned)
    }

    private func teamLine(abbr: String, score: Int) -> some View {
        HStack(spacing: 8) {
            Text(abbr).font(.body.weight(.medium)).lineLimit(1)
            Spacer(minLength: 4)
            if game.status != .scheduled {
                Text("\(score)").font(.body.weight(.bold).monospacedDigit())
            }
        }
    }
}

/// Shared right-hand column: status line (green/orange when live) over the pin marker.
private func statusColumn(line: String, phase: LiveStatusDot.Phase?, pinned: Bool) -> some View {
    VStack(alignment: .trailing, spacing: 4) {
        HStack(spacing: 5) {
            LiveStatusDot(phase: phase)
            Text(line)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusTint(phase))
        }
        Image(systemName: pinned ? "pin.fill" : "pin")
            .font(.caption)
            .foregroundStyle(pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }
}

private func statusTint(_ phase: LiveStatusDot.Phase?) -> Color {
    switch phase {
    case .playing: .green
    case .break: .orange
    case nil: .secondary
    }
}
