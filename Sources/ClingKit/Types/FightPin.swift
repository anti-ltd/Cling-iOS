/**
 The Fight pin: a live UFC event in the Dynamic Island. It follows the *card* —
 always showing the bout currently in play (round + clock), the next bout before
 the card starts, or the result once a bout is decided. The state changes via
 server-pushed Live Activity updates (see `ActivityPushContract`), so a finish
 lands in the island with Cling closed.

 Same plugin shape as `MatchPin`; only the payload and presentation differ
 (fighters + round/clock instead of teams + score). The shared transport — feed
 client, foreground poller, push Worker — keys off `SportLeague`, so this type
 adds a sport without touching any of it.
 */
import SwiftUI
import iUXiOS

@MainActor
public enum FightPinModule: PinModule {
    public static let typeID: PinTypeID = .fight
    public static let displayName = "UFC"
    public static let systemImage = "figure.martial.arts"
    public static let symbolChoices = [
        "figure.martial.arts", "figure.boxing", "trophy.fill", "flame.fill",
        "bolt.fill", "shield.lefthalf.filled", "hand.raised.fill", "star.fill",
    ]

    private static func fight(_ payload: PinPayload) -> FightPayload? {
        if case .fight(let f) = payload { return f }
        return nil
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(FightQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        guard let f = fight(pin.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            PinListFightRow(fight: f, accent: pin.appearance.accent.color)
        )
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        guard let f = fight(ctx.payload) else { return AnyView(EmptyView()) }
        let compact = ctx.density == .compact
        return AnyView(
            VStack(spacing: compact ? 4 : 8) {
                MatchupHeroRow(spacing: 10) {
                    fighterCorner(f.redLast, winner: f.winner == .red, decided: f.status == .finished, compact: compact)
                } center: {
                    centerStat(f, ctx: ctx, compact: compact)
                } trailing: {
                    fighterCorner(f.blueLast, winner: f.winner == .blue, decided: f.status == .finished, compact: compact)
                }
                HStack(spacing: 6) {
                    liveDot(f)
                    Text(f.boutName.isEmpty ? f.eventName : "\(f.eventName) · \(f.boutName)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        guard let f = fight(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            fighterCorner(f.redLast, winner: f.winner == .red, decided: f.status == .finished, compact: true)
                .padding(.leading, 4).padding(.top, 2)
        )
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let f = fight(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            fighterCorner(f.blueLast, winner: f.winner == .blue, decided: f.status == .finished, compact: true)
                .padding(.trailing, 4).padding(.top, 2)
        )
    }

    public static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView {
        guard let f = fight(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(centerStat(f, ctx: ctx, compact: true))
    }

    public static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView? {
        guard let f = fight(ctx.payload) else { return nil }
        return AnyView(
            HStack(spacing: 6) {
                liveDot(f)
                Text(f.boutName.isEmpty ? f.eventName : "\(f.eventName) · \(f.boutName)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        )
    }

    public static func diCompactLeading(_ ctx: PinRenderContext) -> AnyView {
        guard let f = fight(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            Text(f.redLast)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: 56)
        )
    }

    public static func diCompactTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let f = fight(ctx.payload) else { return AnyView(EmptyView()) }
        // Live: the round/clock is the glanceable thing. Otherwise the other
        // fighter's name, so the island still reads as a matchup.
        return AnyView(
            Group {
                if let rc = f.roundClock {
                    Text(rc)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(ctx.accent)
                } else {
                    Text(f.blueLast)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 56)
                }
            }
        )
    }

    public static func diMinimal(_ ctx: PinRenderContext) -> AnyView {
        guard let f = fight(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            Group {
                if let round = f.round, f.status == .live {
                    Text("R\(round)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ctx.accent)
                } else {
                    Image(systemName: ctx.appearance.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ctx.accent)
                }
            }
        )
    }

    public static func liveRow(_ ctx: PinRenderContext) -> AnyView {
        guard let f = fight(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 8) {
                Text("\(f.redLast) vs \(f.blueLast)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(f.statusLine())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
        )
    }

    // MARK: Bits

    /// A fighter's last name; bolded as the winner / dimmed as the loser once a
    /// bout is decided, plain otherwise.
    private static func fighterCorner(_ name: String, winner: Bool, decided: Bool, compact: Bool) -> some View {
        Text(name)
            .font((compact ? Font.subheadline : .headline).weight(decided && winner ? .heavy : .semibold))
            .foregroundStyle(decided && !winner ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// The middle of the island: round+clock live, "vs" before, method/"def."
    /// once decided.
    private static func centerStat(_ f: FightPayload, ctx: PinRenderContext, compact: Bool) -> some View {
        Group {
            if let rc = f.roundClock {
                Text(rc)
            } else if f.status == .finished {
                Text(f.method ?? "def.")
            } else {
                Text("vs")
            }
        }
        .font((compact ? Font.subheadline : .title3).weight(.bold).monospacedDigit())
        .foregroundStyle(ctx.accent)
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private static func liveDot(_ f: FightPayload) -> some View {
        LiveStatusDot(fight: f)
    }
}

/// Two fighter names + the event — enough to create a card manually; a live
/// feed takes over round/clock/result from there via push.
private struct FightQuickAddForm: View {
    @Binding var draft: PinDraft
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextFieldRow(prompt: "Event (e.g. UFC 300)", text: $draft.fightEventName)
                .focused($focused)
                .onAppear { focused = true }
            HStack(spacing: 12) {
                nameField(prompt: "Red corner", text: $draft.fightRedName)
                Text("vs").font(.headline).foregroundStyle(.secondary)
                nameField(prompt: "Blue corner", text: $draft.fightBlueName)
            }
            Text("The live round, clock and result arrive once the card is connected to the feed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func nameField(prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .autocorrectionDisabled()
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Capsule().fill(.ultraThinMaterial))
    }
}
