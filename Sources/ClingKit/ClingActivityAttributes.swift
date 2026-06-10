/**
 The ONE `ActivityAttributes` for all pins. ActivityKit binds each widget
 `ActivityConfiguration` to a single concrete attributes type, so heterogeneous
 pin content travels as the `PinPayload` enum and fans out to per-type
 renderers in the widget (see `PinModule` / `PinRegistry`).
 */
import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct ClingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var payload: PinPayload
        /// In ContentState — not attributes — so editing a pin's colour/icon
        /// updates the live activity without restarting it.
        public var appearance: PinAppearance
        /// When this content goes stale — mirrored into the state so the
        /// renderers can surface expiry honestly ("pinned until 21:40").
        public var staleDate: Date?

        public init(payload: PinPayload, appearance: PinAppearance, staleDate: Date? = nil) {
            self.payload = payload
            self.appearance = appearance
            self.staleDate = staleDate
        }
    }

    /// Immutable for the activity's life.
    public var pinID: UUID
    public var typeID: PinTypeID

    public init(pinID: UUID, typeID: PinTypeID) {
        self.pinID = pinID
        self.typeID = typeID
    }
}

public extension ClingActivityAttributes {
    /// The render context the per-type views consume.
    func renderContext(_ state: ContentState) -> PinRenderContext {
        PinRenderContext(
            pinID: pinID,
            payload: state.payload,
            appearance: state.appearance,
            staleDate: state.staleDate)
    }
}
#endif
