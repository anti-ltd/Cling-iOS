/**
 The Match pin: a live football score in the Dynamic Island. Two teams as flag
 + FIFA code, the running score in the center, and the minute/HT/FT under it.

 What makes it *live*: the score, minute and status ride in the activity's
 `ContentState`, so a server pushing a fresh state over APNs (see
 `ActivityPushContract`) updates the island on a goal with Cling closed — the
 whole point of replicating a World-Cup-score app. The views here are pure
 functions of the payload; they don't poll or fetch.

 Crests deliberately aren't drawn: an image can't ride the 4KB push budget, so
 identity is carried by the FIFA code and rendered as a flag emoji
 (`MatchPayload.flag(for:)`).
 */
import SwiftUI
import iUXiOS

@MainActor
public enum MatchPinModule: PinModule {
    public static let typeID: PinTypeID = .match
    public static let displayName = "Match"
    public static let systemImage = "soccerball"
    // Created through the unified Game composer (World Cup league option), so it
    // stays renderable but out of the quick-add switcher. See `PinDraft.payload`.
    public static let isCreatable = false
    public static let symbolChoices = [
        "soccerball", "sportscourt.fill", "flag.checkered", "trophy.fill",
        "figure.soccer", "star.fill", "globe", "rosette",
    ]

    private static func match(_ payload: PinPayload) -> MatchPayload? {
        if case .match(let m) = payload { return m }
        return nil
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(MatchQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        guard let m = match(pin.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            PinListMatchRow(match: m, accent: pin.appearance.accent.color)
        )
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        guard let m = match(ctx.payload) else { return AnyView(EmptyView()) }
        let compact = ctx.density == .compact
        return AnyView(
            VStack(spacing: compact ? 6 : 8) {
                SportsLockScreen.matchCard(m, accent: ctx.accent, compact: compact)
                playByPlay(m, ctx: ctx, compact: compact)
            }
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
        guard let m = match(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(SportsDIExpanded.matchCenter(m, accent: ctx.accent))
    }

    public static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView? {
        guard let m = match(ctx.payload) else { return nil }
        // Same play-by-play line the lock screen draws — the expanded Island has
        // the room, and it's the only DI region that can carry the commentary.
        return AnyView(playByPlay(m, ctx: ctx, compact: false).padding(.top, 2))
    }

    public static func diCompactLeading(_ ctx: PinRenderContext) -> AnyView {
        guard let m = match(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            SportsDICompact.matchLeading(m, accent: ctx.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    public static func diCompactTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let m = match(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            SportsDICompact.matchTrailing(m, accent: ctx.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        )
    }

    public static func diMinimal(_ ctx: PinRenderContext) -> AnyView {
        guard let m = match(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(SportsDICompact.matchMinimal(m, accent: ctx.accent))
    }

    public static func liveRow(_ ctx: PinRenderContext) -> AnyView {
        guard let m = match(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 6) {
                FlagImage(m.homeCode, size: 18)
                Text(m.scoreText)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                FlagImage(m.awayCode, size: 18)
                (SportsLockScreen.liveClockText(m) ?? Text(m.statusLine()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
        )
    }

    // MARK: Bits

    /// The live play-by-play line under the score — an accent bar + the feed's
    /// latest commentary ("… takes a throw-in"), matching the single-match
    /// reference card. Drawn only when the user's setting is on and the feed has
    /// given us a line; otherwise the card stays score-only.
    @ViewBuilder
    private static func playByPlay(_ m: MatchPayload, ctx: PinRenderContext, compact: Bool) -> some View {
        if ClingStore.shared.loadSettings().matchPlayByPlay,
           let event = m.lastEvent, !event.isEmpty {
            // The accent bar is an overlay on the text, not a flex sibling: the
            // text defines the height so the bar matches it exactly. (A
            // RoundedRectangle has zero intrinsic height — as an HStack sibling
            // under fixedSize it collapses to a sliver in the corner.)
            Text(event)
                .font((compact ? Font.caption2 : .footnote).weight(.medium))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(ctx.accent)
                        .frame(width: 3)
                }
                .padding(.horizontal, 4)
        }
    }
}

/// Two FIFA codes — that's all a manually-created match needs; it starts 0–0,
/// scheduled, and a live feed takes the score from there via push.
private struct MatchQuickAddForm: View {
    @Binding var draft: PinDraft
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Team codes")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                codeField(prompt: "Home", text: $draft.matchHomeCode)
                    .focused($focused)
                    .onAppear { focused = true }
                Text("vs").font(.headline).foregroundStyle(.secondary)
                codeField(prompt: "Away", text: $draft.matchAwayCode)
            }
            if let preview {
                Text(preview)
                    .font(.title3.monospacedDigit())
                    .frame(maxWidth: .infinity)
            }
            Text("FIFA 3-letter codes — ARG, FRA, BRA. The live score arrives once the match is connected to the feed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var preview: String? {
        let home = MatchPayload.normalizeCode(draft.matchHomeCode)
        let away = MatchPayload.normalizeCode(draft.matchAwayCode)
        guard !home.isEmpty, !away.isEmpty else { return nil }
        return "\(MatchPayload.flag(for: home)) \(home)  0–0  \(away) \(MatchPayload.flag(for: away))"
    }

    private func codeField(prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .multilineTextAlignment(.center)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(.ultraThinMaterial))
    }
}
