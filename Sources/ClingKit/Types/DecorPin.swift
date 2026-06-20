/**
 The Decor pin: a content-free presence in the Dynamic Island. It exists only
 to wear the house style (`GlobalPinStyle`) — a glyph in the pin's accent, with
 an optional short caption. No action, no payload to speak of; the look IS the
 point. Use it to dress the island without pinning a note/timer/parking.
 */
import SwiftUI
import iUXiOS

@MainActor
public enum DecorPinModule: PinModule {
    public static let typeID: PinTypeID = .decor
    public static let displayName = "Decoration"
    public static let systemImage = "sparkles"
    public static let symbolChoices = [
        "sparkles", "star.fill", "heart.fill", "moon.stars.fill", "flame.fill",
        "bolt.fill", "leaf.fill", "crown.fill", "music.note", "circle.hexagongrid.fill",
        "drop.fill", "wand.and.stars",
    ]

    private static func decor(_ payload: PinPayload) -> DecorPayload? {
        if case .decor(let d) = payload { return d }
        return nil
    }

    private static func caption(_ payload: PinPayload) -> String? {
        decor(payload)?.displayLabel
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(DecorQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: pin.appearance)
                Text(caption(pin.payload) ?? displayName)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        )
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        let compact = ctx.density == .compact
        return AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: ctx.appearance, size: compact ? 30 : 38)
                if let caption = caption(ctx.payload) {
                    Text(caption)
                        .font(compact ? .subheadline : .body)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        )
    }

    public static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Group {
                if let caption = caption(ctx.payload) {
                    Text(caption)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                } else {
                    EmptyView()
                }
            }
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        // Inset from the island's rounded corner so the curve doesn't clip the
        // badge — same treatment the other types use.
        AnyView(
            PinGlyph(appearance: ctx.appearance, size: 40)
                .padding(.leading, 4)
                .padding(.top, 2)
        )
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        AnyView(EmptyView())
    }

    public static func diCompactLeading(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Image(systemName: ctx.appearance.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ctx.accent)
        )
    }

    public static func diCompactTrailing(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Group {
                if let caption = caption(ctx.payload) {
                    Text(caption)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: 72)
                } else {
                    EmptyView()
                }
            }
        )
    }

    // diMinimal and liveRow use the protocol's glyph defaults — exactly right
    // for a decoration.
}

/// Just a caption field — a decoration is valid empty, so this is optional
/// flourish, not required input.
private struct DecorQuickAddForm: View {
    @Binding var draft: PinDraft
    @FocusState private var focused: Bool

    var body: some View {
        TextFieldRow(prompt: "Caption (optional)", text: $draft.decorLabel)
            .focused($focused)
            .onAppear { focused = true }
    }
}
