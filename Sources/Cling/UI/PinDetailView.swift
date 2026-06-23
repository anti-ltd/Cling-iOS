/**
 One pin, in full — led by the lock-screen stage (the pin shown the way it
 actually lives), then its primary action, type-specific extras (map for
 parking), a quiet stat strip, the appearance entry, and removal.
 */
import SwiftUI
import CoreLocation
import iUXiOS

struct PinDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pin: Pin

    var body: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                // The hero: the pin as the lock screen shows it. What you see is
                // what you pinned.
                LockScreenStage(
                    typeID: pin.typeID,
                    payload: pin.payload,
                    appearance: pin.appearance,
                    staleDate: pin.staleDate)
                    .padding(.top, 4)

                primaryAction

                typeExtras

                appearanceTile

                statStrip

                Button(role: .destructive) {
                    model.delete(pin)
                    #if canImport(UIKit)
                    Haptics.success()
                    #endif
                    dismiss()
                } label: {
                    Label("Remove pin", systemImage: "pin.slash")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassBloom)
                .glassPill(tint: .red)
                .padding(.top, 4)
            }
            .padding(UX.screenPadding)
        }
        .background {
            AmbientBackdrop(tints: [pin.appearance.accent.color,
                                    pin.appearance.accentEnd?.color].compactMap(\.self))
                .ignoresSafeArea()
        }
        .navigationTitle(PinRegistry.module(for: pin.typeID).displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Primary action

    /// The one thing you most likely opened this pin to do — front and centre,
    /// in the pin's own accent. Types without a signature action show nothing.
    @ViewBuilder private var primaryAction: some View {
        switch pin.payload {
        case .parking(let parking):
            AccentActionButton(title: "Walk", systemImage: "figure.walk",
                               accent: pin.appearance.accentGradient) {
                openInMaps(parking)
            }
        case .note(let note) where !note.text.isEmpty:
            AccentActionButton(title: "Copy", systemImage: "doc.on.doc",
                               accent: pin.appearance.accentGradient) {
                #if canImport(UIKit)
                UIPasteboard.general.string = note.text
                Haptics.success()
                #endif
            }
        case .note, .timer, .decor, .match, .fight, .game, .ticker:
            EmptyView()
        }
    }

    // MARK: - Type extras

    @ViewBuilder private var typeExtras: some View {
        if case .parking(let parking) = pin.payload {
            CardSection("Where", accentRule: true) {
                MapSnippet(
                    coordinate: CLLocationCoordinate2D(
                        latitude: parking.latitude, longitude: parking.longitude),
                    tint: pin.appearance.accent.color)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous))
                    .padding(.vertical, UX.rowVPadding)
            }
        }
        if case .game(let game) = pin.payload {
            RecentFormSection(
                leaguePath: game.league,
                homeKey: game.homeAbbr, homeLabel: game.homeAbbr,
                awayKey: game.awayAbbr, awayLabel: game.awayAbbr,
                reloadID: game.sourceID)
        }
        if case .match(let match) = pin.payload {
            CommentarySection(leaguePath: match.league, eventID: match.sourceID)
            RecentFormSection(
                leaguePath: match.league,
                homeKey: match.homeCode, homeLabel: match.homeLabel,
                awayKey: match.awayCode, awayLabel: match.awayLabel,
                reloadID: match.sourceID)
        }
    }

    // MARK: - Appearance entry

    /// A tile that previews the pin's current look — accent glyph + a one-line
    /// summary — and pushes the editor. Richer than a bare settings row.
    private var appearanceTile: some View {
        CardSection {
            NavigationLink {
                PinAppearanceEditorView(pin: pin)
            } label: {
                HStack(spacing: 12) {
                    PinGlyph(appearance: pin.appearance, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appearance")
                            .foregroundStyle(.primary)
                        Text("Color, icon, density, surface")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, UX.rowVPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stat strip

    /// Type and creation time as a quiet two-up footer — facts worth keeping,
    /// but not worth a whole card.
    private var statStrip: some View {
        HStack(spacing: 10) {
            stat("Type", PinRegistry.module(for: pin.typeID).displayName)
            stat("Created", pin.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let endDate = pin.endDate {
                stat("Ends", endDate.formatted(date: .omitted, time: .shortened))
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassTile()
    }

    private func openInMaps(_ parking: ParkingPayload) {
        let coordinate = "\(parking.latitude),\(parking.longitude)"
        if let url = URL(string: "maps://?daddr=\(coordinate)&dirflg=w") {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }
}

// MARK: - Accent action button

/// A full-width, accent-filled call to action — the pin's primary verb, in the
/// pin's own colour. Mirrors the glass language: sheen highlight, lit rim,
/// press bloom.
struct AccentActionButton: View {
    let title: String
    let systemImage: String
    let accent: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background {
                    let rr = RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous)
                    rr.fill(accent)
                        .overlay(rr.fill(
                            LinearGradient(colors: [.white.opacity(UX.Glass.sheenTopOpacity), .clear],
                                           startPoint: .top, endPoint: .bottom)))
                        .overlay(rr.strokeBorder(.white.opacity(UX.Glass.rimTopOpacity),
                                                 lineWidth: UX.Glass.rimWidth))
                }
        }
        .buttonStyle(.glassBloom)
    }
}

// MARK: - Commentary timeline

/// A match's play-by-play, pulled from ESPN when the detail opens. The Live
/// Activity carries only the latest line (4KB push budget); this is the full
/// history, newest first. In-app only — hides itself when the feed has nothing
/// (a hand-made match with no fixture, no commentary yet, or no network).
private struct CommentarySection: View {
    let leaguePath: String
    /// ESPN event id; nil for a hand-made match → nothing to fetch.
    let eventID: String?

    @State private var entries: [CommentaryEntry] = []
    @State private var phase: Phase = .loading

    private enum Phase { case loading, loaded, empty }

    var body: some View {
        switch phase {
        case .loading:
            CardSection("Commentary", accentRule: true) {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .task(id: eventID) { await load() }
        case .loaded:
            CardSection("Commentary", accentRule: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        row(entry)
                    }
                }
            }
        case .empty:
            EmptyView()
        }
    }

    private func row(_ e: CommentaryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(e.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint(e.kind))
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.text)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !e.minute.isEmpty {
                    Text(e.minute)
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    private func icon(_ k: CommentaryEntry.Kind) -> String {
        switch k {
        case .goal:         "soccerball.inverse"
        case .card:         "rectangle.portrait.fill"
        case .substitution: "arrow.left.arrow.right"
        case .penalty:      "scope"
        case .whistle:      "flag.checkered"
        case .other:        "circle.fill"
        }
    }

    private func tint(_ k: CommentaryEntry.Kind) -> Color {
        switch k {
        case .goal:         .green
        case .card:         .yellow
        case .substitution: .blue
        case .penalty:      .orange
        case .whistle:      .gray
        case .other:        .gray.opacity(0.5)
        }
    }

    private func load() async {
        phase = .loading
        let list = (try? await MatchCommentary.fetch(leaguePath: leaguePath, eventID: eventID ?? "")) ?? []
        entries = list
        phase = list.isEmpty ? .empty : .loaded
    }
}

// MARK: - Recent form

/// The two sides' last few results, pulled from each team's schedule when the
/// pin detail opens. Serves both team games (NBA/NFL/NHL/MLB, keyed by league
/// abbreviation) and World Cup matches (keyed by FIFA code) — the ESPN schedule
/// endpoint takes either. In-app only: keeps the lock-screen pin lean while the
/// detail screen carries the history, and hides itself when the feed has nothing
/// (off-season, an unknown code, or no network).
private struct RecentFormSection: View {
    let leaguePath: String
    let homeKey: String
    let homeLabel: String
    let awayKey: String
    let awayLabel: String
    /// Re-fetch when the tracked fixture changes.
    let reloadID: String?

    @State private var home: [TeamResult] = []
    @State private var away: [TeamResult] = []
    @State private var phase: Phase = .loading

    private enum Phase { case loading, loaded, empty }

    var body: some View {
        switch phase {
        case .loading:
            CardSection("Recent form", accentRule: true) {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .task(id: reloadID) { await load() }
        case .loaded:
            CardSection("Recent form", accentRule: true) {
                teamForm(label: homeLabel, results: home)
                if !home.isEmpty && !away.isEmpty { Divider() }
                teamForm(label: awayLabel, results: away)
            }
        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder private func teamForm(label: String, results: [TeamResult]) -> some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(label).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(record(results))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                ForEach(results) { r in
                    Divider()
                    resultRow(r)
                }
            }
        }
    }

    private func resultRow(_ r: TeamResult) -> some View {
        HStack(spacing: 8) {
            Text(r.matchup).font(.footnote.weight(.medium))
            Spacer(minLength: 8)
            Text(r.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(r.scoreLine)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(color(r.outcome))
                .frame(minWidth: 76, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    private func color(_ outcome: Outcome) -> Color {
        switch outcome {
        case .win:  .green
        case .draw: .gray
        case .loss: .red
        }
    }

    /// Record over the fetched window — "3–2", or "2–1–2" once draws appear.
    private func record(_ results: [TeamResult]) -> String {
        let w = results.filter { $0.outcome == .win }.count
        let d = results.filter { $0.outcome == .draw }.count
        let l = results.filter { $0.outcome == .loss }.count
        return d > 0 ? "\(w)–\(d)–\(l)" : "\(w)–\(l)"
    }

    private func load() async {
        phase = .loading
        async let h = try? TeamFormFeed.recent(leaguePath: leaguePath, teamAbbr: homeKey)
        async let a = try? TeamFormFeed.recent(leaguePath: leaguePath, teamAbbr: awayKey)
        let homeResults = await h ?? []
        let awayResults = await a ?? []
        home = homeResults
        away = awayResults
        phase = (homeResults.isEmpty && awayResults.isEmpty) ? .empty : .loaded
    }
}
