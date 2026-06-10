/**
 The pin-type plugin contract. One conforming type per pin type, registered in
 `PinRegistry`, owning everything type-specific: glyph, validation, the
 quick-add form, the list row, and every Live Activity presentation.

 `AnyView` at this boundary is deliberate: the registry is heterogeneous, the
 view trees are tiny, and Live Activity views are re-rendered wholesale by the
 system — there's no diffing win to protect.

 Adding a pin type = a `PinPayload` case (the compiler then walks you through
 every exhaustive switch), one new file conforming to this protocol, and one
 registry line. See ARCHITECTURE.md.
 */
import SwiftUI

/// Everything a renderer needs, decoded once from activity attributes + state.
/// Deliberately free of ActivityKit types so the same renderers serve in-app
/// previews (the appearance editor shows the literal activity views).
public struct PinRenderContext: Sendable {
    public let pinID: UUID
    public let payload: PinPayload
    public let appearance: PinAppearance
    /// When the activity goes stale — nil in contexts without one (in-app
    /// previews). Renderers may surface it; the shared lock-screen chrome
    /// already does.
    public let staleDate: Date?

    public init(pinID: UUID, payload: PinPayload, appearance: PinAppearance, staleDate: Date? = nil) {
        self.pinID = pinID
        self.payload = payload
        self.appearance = appearance
        self.staleDate = staleDate
    }

    /// Convenience for renderers.
    public var accent: Color { appearance.accent.color }
    public var density: LayoutDensity { appearance.density }
}

/// The in-progress state of the quick-add composer — one shared draft struct
/// (rather than per-type generics) so the composer can switch types without
/// losing what's already typed.
public struct PinDraft: Sendable, Equatable {
    public var typeID: PinTypeID
    /// Note / clipboard text.
    public var text: String
    /// Timer label.
    public var label: String
    /// Parking headline override ("Parked here" when empty).
    public var title: String
    public var duration: TimeInterval
    /// Parking fields — filled by app-side location/photo pickers.
    public var parkingNote: String
    public var latitude: Double?
    public var longitude: Double?
    public var photoFilename: String?
    /// Clipboard provenance, when shared from a web page.
    public var sourceURL: URL?

    public init(typeID: PinTypeID = .note) {
        self.typeID = typeID
        self.text = ""
        self.label = ""
        self.title = ""
        self.duration = 15 * 60
        self.parkingNote = ""
    }

    /// The payload this draft describes, or nil while it's incomplete.
    public func payload(now: Date = .now) -> PinPayload? {
        switch typeID {
        case .note:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || photoFilename != nil else { return nil }
            return .note(NotePayload(text: trimmed, photoFilename: photoFilename))
        case .timer:
            guard duration > 0 else { return nil }
            return .timer(TimerPayload(
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: now,
                endDate: now.addingTimeInterval(duration)))
        case .parking:
            guard let latitude, let longitude else { return nil }
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = parkingNote.trimmingCharacters(in: .whitespacesAndNewlines)
            return .parking(ParkingPayload(
                latitude: latitude, longitude: longitude,
                title: title.isEmpty ? nil : title,
                note: note.isEmpty ? nil : note,
                photoFilename: photoFilename))
        case .clipboard:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .clipboard(ClipboardPayload(text: trimmed, sourceURL: sourceURL))
        }
    }
}

@MainActor
public protocol PinModule {
    static var typeID: PinTypeID { get }
    static var displayName: String { get }
    /// The type's default glyph (users can swap it per pin).
    static var systemImage: String { get }
    /// The SF Symbols offered for this type in the appearance editor.
    static var symbolChoices: [String] { get }

    /// nil when valid; a user-facing message otherwise.
    static func validate(_ payload: PinPayload) -> String?

    // App-side views

    /// The type-specific fields of the quick-add composer.
    static func quickAddForm(draft: Binding<PinDraft>) -> AnyView
    /// The pin's row in the main list.
    static func listRow(_ pin: Pin) -> AnyView

    // Live Activity views — run in the widget process; must not touch app
    // state. iUX glass modifiers and tokens are safe; navigation is not.

    static func lockScreen(_ ctx: PinRenderContext) -> AnyView
    static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView
    static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView
    static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView
    /// Optional bottom region of the expanded island; nil to omit.
    static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView?
    static func diCompactLeading(_ ctx: PinRenderContext) -> AnyView
    static func diCompactTrailing(_ ctx: PinRenderContext) -> AnyView
    static func diMinimal(_ ctx: PinRenderContext) -> AnyView
}

public extension PinModule {
    /// Most types validate at draft time; payloads are well-formed by
    /// construction. Override for types with semantic constraints (e.g. a
    /// timer whose end must be in the future).
    static func validate(_ payload: PinPayload) -> String? { nil }

    static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView? { nil }

    /// Shared minimal presentation: the pin's glyph in its accent. Types
    /// override only when they have something more glanceable (a countdown).
    static func diMinimal(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Image(systemName: ctx.appearance.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ctx.accent)
        )
    }
}
