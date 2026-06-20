/**
 The Note pin: a short text held in view. The simplest module — the reference
 implementation for new pin types.
 */
import SwiftUI
import iUXiOS
import AppIntents

/// Copies a note's text to the clipboard from a Dynamic Island button. A
/// `LiveActivityIntent` (iOS 17.2+) runs in the app's process without
/// foregrounding — Cling's 17.2 floor is exactly for this. Lives in ClingKit
/// so the widget can reference it in `Button(intent:)` and the app can run it.
struct CopyNoteTextIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Copy Note"
    // It's a button action on the activity, not something to surface in Shortcuts.
    static let isDiscoverable = false

    @Parameter(title: "Text") var text: String

    init() {}
    init(text: String) { self.text = text }

    func perform() async throws -> some IntentResult {
        #if canImport(UIKit)
        let copy = text
        await MainActor.run { UIPasteboard.general.string = copy }
        #endif
        return .result()
    }
}

@MainActor
public enum NotePinModule: PinModule {
    public static let typeID: PinTypeID = .note
    public static let displayName = "Note"
    public static let systemImage = "note.text"
    public static let symbolChoices = [
        "note.text", "lightbulb.fill", "exclamationmark.bubble.fill",
        "checklist", "heart.fill", "star.fill", "flag.fill", "brain.fill",
        "doc.on.clipboard", "link", "key.fill", "number",
    ]

    private static func note(_ payload: PinPayload) -> NotePayload? {
        if case .note(let note) = payload { return note }
        return nil
    }

    private static func text(_ payload: PinPayload) -> String {
        note(payload)?.text ?? ""
    }

    /// The host of the note's source page, when it was shared from the web.
    private static func sourceHost(_ payload: PinPayload) -> String? {
        note(payload)?.sourceURL?.host()
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(text(pin.payload))
                        .font(.body)
                        .lineLimit(2)
                    if let host = sourceHost(pin.payload) {
                        Text(host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(text(ctx.payload))
                        .font(compact ? .subheadline : .body)
                        .lineLimit(compact ? 2 : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let host = sourceHost(ctx.payload) {
                        Text(host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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
        // Inset from the island's rounded corner — otherwise the corner curve
        // clips the badge's top-left.
        AnyView(
            PinGlyph(appearance: ctx.appearance, size: 40)
                .padding(.leading, 4)
                .padding(.top, 2)
        )
    }

    /// Quick-copy: an interactive button (not a Link) that runs
    /// `CopyNoteTextIntent` in the app process, leaving the activity up.
    public static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView? {
        let noteText = text(ctx.payload)
        guard !noteText.isEmpty else { return nil }
        return AnyView(
            Button(intent: CopyNoteTextIntent(text: noteText)) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Copy")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(ctx.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.top, 4)
        )
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        AnyView(thumb(ctx.payload, size: 28))
    }

    public static func liveRow(_ ctx: PinRenderContext) -> AnyView {
        let noteText = text(ctx.payload)
        return AnyView(
            HStack(spacing: 10) {
                PinGlyph(appearance: ctx.appearance, size: 30)
                Text(noteText.isEmpty ? displayName : noteText)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if !noteText.isEmpty {
                    Button(intent: CopyNoteTextIntent(text: noteText)) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 32)
                            .background(ctx.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
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
        VStack(spacing: 0) {
            TextFieldRow(prompt: "What should I hold on to?", text: $draft.text, axis: .vertical)
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
