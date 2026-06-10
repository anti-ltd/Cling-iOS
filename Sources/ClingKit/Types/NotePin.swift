/**
 The Note pin: a short text held in view. The simplest module — the reference
 implementation for new pin types.
 */
import SwiftUI
import iUXiOS

@MainActor
public enum NotePinModule: PinModule {
    public static let typeID: PinTypeID = .note
    public static let displayName = "Note"
    public static let systemImage = "note.text"
    public static let symbolChoices = [
        "note.text", "lightbulb.fill", "exclamationmark.bubble.fill",
        "checklist", "heart.fill", "star.fill", "flag.fill", "brain.fill",
    ]

    private static func note(_ payload: PinPayload) -> NotePayload? {
        if case .note(let note) = payload { return note }
        return nil
    }

    private static func text(_ payload: PinPayload) -> String {
        note(payload)?.text ?? ""
    }

    /// The note's photo, loaded from the shared container (widget-safe).
    @ViewBuilder private static func thumb(_ payload: PinPayload, size: CGFloat) -> some View {
        if let filename = note(payload)?.photoFilename {
            #if canImport(UIKit)
            GlassThumb(
                image: PhotoStore.shared.loadImage(filename).map(Image.init(uiImage:)),
                size: CGSize(width: size, height: size),
                placeholderSymbol: "photo")
            #else
            GlassThumb(image: nil, size: CGSize(width: size, height: size), placeholderSymbol: "photo")
            #endif
        }
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(NoteQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: pin.appearance)
                Text(text(pin.payload))
                    .font(.body)
                    .lineLimit(2)
                Spacer(minLength: 0)
                thumb(pin.payload, size: 40)
            }
        )
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        let compact = ctx.density == .compact
        return AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: ctx.appearance,
                         size: compact ? 30 : 38)
                Text(text(ctx.payload))
                    .font(compact ? .subheadline : .body)
                    .lineLimit(compact ? 2 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                thumb(ctx.payload, size: compact ? 36 : 48)
            }
        )
    }

    public static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Text(text(ctx.payload))
                .font(.subheadline)
                .lineLimit(ctx.density == .compact ? 2 : 3)
                .multilineTextAlignment(.center)
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        AnyView(PinGlyph(appearance: ctx.appearance, size: 28))
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        AnyView(thumb(ctx.payload, size: 28))
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
            Text(text(ctx.payload))
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: 72)
        )
    }
}

/// Keyboard-first: the field is focused the moment the form appears, and
/// return submits via the composer's primary action.
private struct NoteQuickAddForm: View {
    @Binding var draft: PinDraft
    @FocusState private var focused: Bool

    var body: some View {
        TextFieldRow(prompt: "What should I hold on to?", text: $draft.text, axis: .vertical)
            .focused($focused)
            .onAppear { focused = true }
    }
}
