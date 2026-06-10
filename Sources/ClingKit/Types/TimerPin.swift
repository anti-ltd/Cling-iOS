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
        return AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: pin.appearance)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer?.label.isEmpty == false ? timer!.label : "Timer")
                        .font(.body)
                    if let timer {
                        Group {
                            if timer.endDate > .now {
                                CountdownText(from: timer.startDate, until: timer.endDate)
                            } else {
                                Text("done")
                            }
                        }
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        )
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        guard let timer = payload(ctx.payload) else { return AnyView(EmptyView()) }
        let compact = ctx.density == .compact
        return AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: ctx.appearance,
                         size: compact ? 30 : 38)
                VStack(alignment: .leading, spacing: 1) {
                    if !timer.label.isEmpty {
                        Text(timer.label)
                            .font(compact ? .caption : .subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    CountdownText(from: timer.startDate, until: timer.endDate)
                        .font(.system(compact ? .title3 : .title, design: .rounded).weight(.semibold))
                        .foregroundStyle(ctx.accent)
                }
                Spacer(minLength: 0)
                if !compact {
                    ProgressView(timerInterval: timer.startDate...timer.endDate, countsDown: true) {
                    } currentValueLabel: {
                    }
                    .progressViewStyle(.circular)
                    .tint(ctx.accent)
                    .frame(width: 32, height: 32)
                }
            }
        )
    }

    public static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView {
        guard let timer = payload(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                if !timer.label.isEmpty {
                    Text(timer.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                CountdownText(from: timer.startDate, until: timer.endDate)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(ctx.accent)
            }
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        AnyView(PinGlyph(appearance: ctx.appearance, size: 28))
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let timer = payload(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            ProgressView(timerInterval: timer.startDate...timer.endDate, countsDown: true) {
            } currentValueLabel: {
            }
            .progressViewStyle(.circular)
            .tint(ctx.accent)
            .frame(width: 28, height: 28)
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
        VStack(spacing: 4) {
            TextFieldRow(prompt: "What's this timer for? (optional)", text: $draft.label)
                .focused($focused)
                .onAppear { focused = true }
            DurationPicker(
                selection: $draft.duration,
                presets: [5 * 60, 15 * 60, 25 * 60, 60 * 60])
        }
    }
}
