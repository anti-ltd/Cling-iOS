/**
 The Clipboard pin: pasted text held one tap from being copied back out. The
 lock-screen card offers a copy affordance (the widget wires it to an intent).
 */
import SwiftUI
import iUXiOS

@MainActor
public enum ClipboardPinModule: PinModule {
    public static let typeID: PinTypeID = .clipboard
    public static let displayName = "Clipboard"
    public static let systemImage = "doc.on.clipboard"
    public static let symbolChoices = [
        "doc.on.clipboard", "doc.on.doc.fill", "link", "key.fill",
        "number", "envelope.fill", "creditcard.fill",
    ]

    private static func payload(_ payload: PinPayload) -> ClipboardPayload? {
        if case .clipboard(let clip) = payload { return clip }
        return nil
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(ClipboardQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        let clip = payload(pin.payload)
        return AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: pin.appearance)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip?.text ?? "")
                        .font(.body.monospaced())
                        .lineLimit(2)
                    if let source = clip?.sourceURL?.host() {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        )
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        let clip = payload(ctx.payload)
        let compact = ctx.density == .compact
        return AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: ctx.appearance,
                         size: compact ? 30 : 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip?.text ?? "")
                        .font((compact ? Font.footnote : .subheadline).monospaced())
                        .lineLimit(compact ? 2 : 3)
                    if let source = clip?.sourceURL?.host() {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ctx.accent)
            }
        )
    }

    public static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Text(payload(ctx.payload)?.text ?? "")
                .font(.subheadline.monospaced())
                .lineLimit(ctx.density == .compact ? 2 : 3)
                .multilineTextAlignment(.center)
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        AnyView(PinGlyph(appearance: ctx.appearance, size: 28))
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Image(systemName: "doc.on.doc")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ctx.accent)
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
            Text(payload(ctx.payload)?.text ?? "")
                .font(.caption2.monospaced())
                .lineLimit(1)
                .frame(maxWidth: 72)
        )
    }
}

private struct ClipboardQuickAddForm: View {
    @Binding var draft: PinDraft
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextFieldRow(prompt: "Paste what you need at hand", text: $draft.text, axis: .vertical)
                .focused($focused)
                .onAppear { focused = true }
            #if canImport(UIKit)
            if draft.text.isEmpty, UIPasteboard.general.hasStrings {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        draft.text = pasted
                    }
                } label: {
                    Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.glassBloom)
                .padding(.bottom, 10)
            }
            #endif
        }
    }
}
