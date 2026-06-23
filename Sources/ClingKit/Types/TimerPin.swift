/**
 The Timer pin: a labelled countdown. Renders via `CountdownText`
 (`Text(timerInterval:)` under the hood) so every tick is drawn client-side —
 zero activity updates spent on the countdown itself.
 */
import SwiftUI
import iUXiOS

@MainActor
public enum TimerPinModule: PinModule {
    public static let typeID: PinTypeID = .timer
    public static let displayName = "Timer"
    public static let systemImage = "timer"
    public static let symbolChoices = [
        "timer", "hourglass", "alarm.fill", "fork.knife",
        "dumbbell.fill", "cup.and.saucer.fill", "airplane.departure",
    ]

    private static func payload(_ payload: PinPayload) -> TimerPayload? {
        if case .timer(let timer) = payload { return timer }
        return nil
    }

    public static func validate(_ payload: PinPayload) -> String? {
        guard let timer = Self.payload(payload) else { return nil }
        guard timer.endDate > .now else { return "The countdown has already passed." }
        return nil
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(TimerQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        let timer = payload(pin.payload)
        return AnyView(TimerListRow(timer: timer, appearance: pin.appearance))
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        guard let timer = payload(ctx.payload) else { return AnyView(EmptyView()) }
        let compact = ctx.density == .compact
        switch timer.style {
        case .text: return textCard(timer, ctx, compact: compact)
        case .ring: return ringCard(timer, ctx, compact: compact)
        case .bar:  return barCard(timer, ctx, compact: compact)
        case .fill: return fillCard(timer, ctx, compact: compact)
        }
    }

    // MARK: Lock-screen card variants

    /// Glyph + label + numerals. The quiet default; no progress geometry.
    private static func textCard(_ timer: TimerPayload, _ ctx: PinRenderContext, compact: Bool) -> AnyView {
        AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: ctx.appearance, size: compact ? 30 : 38)
                labelAndCount(timer, ctx, compact: compact)
                Spacer(minLength: 0)
            }
        )
    }

    /// The numerals beside a circular ring that empties as time runs out.
    private static func ringCard(_ timer: TimerPayload, _ ctx: PinRenderContext, compact: Bool) -> AnyView {
        AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: ctx.appearance, size: compact ? 30 : 38)
                labelAndCount(timer, ctx, compact: compact)
                Spacer(minLength: 0)
                ProgressView(timerInterval: timer.startDate...timer.endDate, countsDown: true) {
                } currentValueLabel: {
                }
                .progressViewStyle(.circular)
                .tint(ctx.accent)
                .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
            }
        )
    }

    /// Numerals over a thin horizontal bar that drains as time runs out.
    private static func barCard(_ timer: TimerPayload, _ ctx: PinRenderContext, compact: Bool) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                HStack(spacing: 12) {
                    PinGlyph(appearance: ctx.appearance, size: compact ? 30 : 38)
                    labelAndCount(timer, ctx, compact: compact)
                    Spacer(minLength: 0)
                }
                drainBar(timer, tint: ctx.accent)
            }
        )
    }

    /// Accent panel filling the card, white numerals on top, a draining gauge
    /// pinned across the bottom. The whole card reads as the timer.
    private static func fillCard(_ timer: TimerPayload, _ ctx: PinRenderContext, compact: Bool) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                HStack(spacing: 12) {
                    PinGlyph(appearance: ctx.appearance, size: compact ? 30 : 38)
                    labelAndCount(timer, ctx, compact: compact, onAccent: true)
                    Spacer(minLength: 0)
                }
                drainBar(timer, tint: .white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, compact ? 10 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AnyShapeStyle(ctx.appearance.accentGradient)))
        )
    }

    /// Shared label + countdown column. `onAccent` flips the colours for the
    /// fill card, where the text sits over the accent panel.
    private static func labelAndCount(_ timer: TimerPayload, _ ctx: PinRenderContext, compact: Bool, onAccent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if !timer.label.isEmpty {
                Text(timer.label)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(onAccent ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            CountdownText(from: timer.startDate, until: timer.endDate)
                .font(.system(compact ? .title3 : .title, design: .rounded).weight(.semibold))
                .foregroundStyle(onAccent ? AnyShapeStyle(.white) : AnyShapeStyle(ctx.accent))
        }
    }

    /// A horizontal bar that drains as the timer runs down. Built on the system
    /// `.linear` style — the ONLY path that auto-ticks inside a Live Activity
    /// (a custom `ProgressViewStyle` gets a frozen `fractionCompleted` snapshot).
    @ViewBuilder
    private static func drainBar(_ timer: TimerPayload, tint: Color) -> some View {
        ProgressView(timerInterval: timer.startDate...timer.endDate, countsDown: true) {
        } currentValueLabel: {
        }
        .progressViewStyle(.linear)
        .tint(tint)
    }

    public static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView {
        guard let timer = payload(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: timer.style == .bar ? 6 : 0) {
                if !timer.label.isEmpty {
                    Text(timer.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                CountdownText(from: timer.startDate, until: timer.endDate)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(ctx.accent)
                if timer.style == .bar || timer.style == .fill {
                    drainBar(timer, tint: ctx.accent)
                        .padding(.horizontal, 12)
                }
            }
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        // Inset from the island's rounded corner — otherwise the corner curve
        // clips the badge's top-left.
        AnyView(
            PinGlyph(appearance: ctx.appearance, size: 40)
                .padding(.leading, 4)
                .padding(.top, 2)
        )
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let timer = payload(ctx.payload) else { return AnyView(EmptyView()) }
        // The bar/fill styles already carry their progress in the centre region;
        // a ring here would double it up, so trailing stays empty for those.
        guard timer.style == .ring || timer.style == .text else { return AnyView(EmptyView()) }
        return AnyView(
            ProgressView(timerInterval: timer.startDate...timer.endDate, countsDown: true) {
            } currentValueLabel: {
            }
            .progressViewStyle(.circular)
            .tint(ctx.accent)
            .frame(width: 28, height: 28)
        )
    }

    public static func liveRow(_ ctx: PinRenderContext) -> AnyView {
        guard let timer = payload(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 10) {
                PinGlyph(appearance: ctx.appearance, size: 30)
                Text(timer.label.isEmpty ? "Timer" : timer.label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                CountdownText(from: timer.startDate, until: timer.endDate)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ctx.accent)
                    .fixedSize()
            }
        )
    }

    public static func diCompactLeading(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Image(systemName: ctx.appearance.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ctx.accent)
        )
    }

    public static func diCompactTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let timer = payload(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            CountdownText(from: timer.startDate, until: timer.endDate)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(ctx.accent)
                .frame(maxWidth: 52)
        )
    }

    /// The countdown IS the minimal presentation — more glanceable than a glyph.
    public static func diMinimal(_ ctx: PinRenderContext) -> AnyView {
        guard let timer = payload(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            CountdownText(from: timer.startDate, until: timer.endDate)
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(ctx.accent)
                .minimumScaleFactor(0.6)
        )
    }
}

private struct TimerQuickAddForm: View {
    @Binding var draft: PinDraft
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextFieldRow(prompt: "What's this timer for? (optional)", text: $draft.label)
                .focused($focused)
                .onAppear { focused = true }
            DurationPicker(
                selection: $draft.duration,
                presets: [5 * 60, 15 * 60, 25 * 60, 60 * 60])
            Text("Countdown")
                .font(.caption)
                .foregroundStyle(.secondary)
            OptionChips(
                options: CountdownStyle.allCases.map { ($0.label, $0) },
                selection: $draft.countdownStyle)
        }
    }
}
