/**
 The Game pin: a live US-league team game (NBA / NFL / NHL / MLB) in the Dynamic
 Island. Two teams, the score, and the period/clock — refreshed via server-
 pushed Live Activity updates (see `ActivityPushContract`), so a go-ahead basket
 or a walk-off lands in the island with Cling closed.

 One module serves all four leagues: only the clock model differs, and that
 rides in `TeamGamePayload.sport`. Same plugin shape as `MatchPin`/`FightPin`;
 the shared transport — feed client, foreground poller, push Worker — keys off
 `SportLeague`, so this type adds four sports without touching any of it.
 */
import SwiftUI
import iUXiOS

@MainActor
public enum GamePinModule: PinModule {
    public static let typeID: PinTypeID = .game
    public static let displayName = "Sports"
    public static let systemImage = "sportscourt.fill"
    public static let symbolChoices = [
        "sportscourt.fill", "soccerball", "basketball.fill", "football.fill",
        "hockey.puck.fill", "baseball.fill", "trophy.fill", "flag.checkered",
    ]

    private static func game(_ payload: PinPayload) -> TeamGamePayload? {
        if case .game(let g) = payload { return g }
        return nil
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(GameQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        guard let g = game(pin.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            PinListGameRow(game: g, accent: pin.appearance.accent.color)
        )
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        guard let g = game(ctx.payload) else { return AnyView(EmptyView()) }
        let compact = ctx.density == .compact
        return AnyView(
            SportsLockScreen.gameCard(g, accent: ctx.accent, compact: compact)
                .frame(maxWidth: .infinity)
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        AnyView(SportsDIExpanded.emptyLeading())
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        AnyView(SportsDIExpanded.emptyTrailing())
    }

    public static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView {
        guard let g = game(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(SportsDIExpanded.gameCenter(g, accent: ctx.accent))
    }

    public static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView? { nil }

    public static func diCompactLeading(_ ctx: PinRenderContext) -> AnyView {
        guard let g = game(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            SportsDICompact.gameLeading(g, accent: ctx.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    public static func diCompactTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let g = game(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            SportsDICompact.gameTrailing(g, accent: ctx.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        )
    }

    public static func diMinimal(_ ctx: PinRenderContext) -> AnyView {
        guard let g = game(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(SportsDICompact.gameMinimal(g, accent: ctx.accent))
    }

    public static func liveRow(_ ctx: PinRenderContext) -> AnyView {
        guard let g = game(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 8) {
                Text("\(g.homeAbbr) \(g.scoreText) \(g.awayAbbr)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                Text(g.statusLine())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
        )
    }
}

/// Pick a league, then pick the two teams from its roster — no codes to type.
/// World Cup lives here too (it routes to a `.match` payload, see
/// `PinDraft.payload`); a live feed takes over the score from there via push.
private struct GameQuickAddForm: View {
    @Binding var draft: PinDraft

    private var teams: [LeagueTeam] { LeagueTeams.teams(for: draft.gameLeague) }
    private var isSoccer: Bool { draft.gameLeague == .worldCup }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("League", selection: $draft.gameLeague) {
                ForEach(LeagueTeams.creatableLeagues, id: \.self) { league in
                    Label(league.label, systemImage: league.systemImage).tag(league)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: draft.gameLeague) { _, _ in
                // Codes from one league don't carry to another.
                draft.gameHomeAbbr = ""
                draft.gameAwayAbbr = ""
            }

            HStack(spacing: 12) {
                teamMenu(prompt: "Home", selection: $draft.gameHomeAbbr, exclude: draft.gameAwayAbbr)
                Text("vs").font(.headline).foregroundStyle(.secondary)
                teamMenu(prompt: "Away", selection: $draft.gameAwayAbbr, exclude: draft.gameHomeAbbr)
            }

            previewRow

            Text("The live score arrives once the \(isSoccer ? "match" : "game") is connected to the feed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A dropdown of the selected league's teams. Shows the chosen team's name
    /// (with its flag for World Cup), or the prompt when nothing's picked.
    private func teamMenu(prompt: String, selection: Binding<String>, exclude: String) -> some View {
        Menu {
            ForEach(teams.filter { $0.abbr != exclude || $0.abbr == selection.wrappedValue }) { team in
                Button {
                    selection.wrappedValue = team.abbr
                } label: {
                    if isSoccer {
                        Text("\(MatchPayload.flag(for: team.abbr)) \(team.name)")
                    } else {
                        Text(team.name)
                    }
                }
            }
        } label: {
            menuLabel(prompt: prompt, abbr: selection.wrappedValue)
        }
    }

    @ViewBuilder
    private func menuLabel(prompt: String, abbr: String) -> some View {
        let picked = teams.first { $0.abbr == abbr }
        HStack(spacing: 6) {
            if let picked {
                if isSoccer { FlagImage(picked.abbr, size: 20) }
                Text(picked.abbr)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            } else {
                Text(prompt).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    /// A "🇦🇷 ARG  0–0  FRA 🇫🇷" / "LAL  0–0  BOS" preview once both teams are set —
    /// real flags for World Cup, codes for the US leagues.
    @ViewBuilder
    private var previewRow: some View {
        let home = draft.gameHomeAbbr.uppercased()
        let away = draft.gameAwayAbbr.uppercased()
        if !home.isEmpty, !away.isEmpty {
            HStack(spacing: 8) {
                if isSoccer { FlagImage(home, size: 22) }
                Text(home).font(.title3.weight(.semibold))
                Text("0–0").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                Text(away).font(.title3.weight(.semibold))
                if isSoccer { FlagImage(away, size: 22) }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
