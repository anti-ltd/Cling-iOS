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

    private static func trailingSymbol(_ payload: PinPayload) -> String? {
        decor(payload)?.trailingSymbol
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(DecorQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        AnyView(
            HStack(spacing: 12) {
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
        // Mirror the leading glyph badge when a trailing symbol is set, so the
        // expanded island reads as a matched pair. Inset from the opposite
        // corner the same way leading insets from its own.
        guard let symbol = trailingSymbol(ctx.payload) else { return AnyView(EmptyView()) }
        var trailingAppearance = ctx.appearance
        trailingAppearance.symbolName = symbol
        return AnyView(
            PinGlyph(appearance: trailingAppearance, size: 40)
                .padding(.trailing, 4)
                .padding(.top, 2)
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
        AnyView(
            Group {
                // A trailing glyph wins the slot — that's the "icon on either
                // side" look. Caption is the fallback when there's no symbol.
                if let symbol = trailingSymbol(ctx.payload) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ctx.accent)
                } else if let caption = caption(ctx.payload) {
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

/// A caption field plus an optional trailing glyph — a decoration is valid
/// empty, so both are optional flourish, not required input. The trailing glyph
/// puts an icon on the far side of the Dynamic Island, framing it on both sides.
private struct DecorQuickAddForm: View {
    @Binding var draft: PinDraft
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextFieldRow(prompt: "Caption (optional)", text: $draft.decorLabel)
                .focused($focused)
                .onAppear { focused = true }

            Text("Trailing glyph")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8, lineSpacing: 8) {
                trailingChip(symbol: nil, label: "None")
                ForEach(DecorPinModule.symbolChoices, id: \.self) { symbol in
                    trailingChip(symbol: symbol, label: nil)
                }
            }
        }
    }

    private func trailingChip(symbol: String?, label: String?) -> some View {
        let selected = draft.decorTrailingSymbol == (symbol ?? "")
        return Button {
            draft.decorTrailingSymbol = symbol ?? ""
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                } else if let label {
                    Text(label).font(.system(size: 13, weight: .medium))
                }
            }
            .font(.system(size: 15, weight: .medium))
            .frame(width: 44, height: 32)
            .background {
                if selected {
                    Capsule().fill(.tint)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.glassBloom)
    }
}
