/**
 The ONE `ActivityAttributes` for the whole app — a *roster*, not a single pin.
 ActivityKit binds each widget `ActivityConfiguration` to a single concrete
 attributes type and shows only one of an app's activities in the Dynamic
 Island, so Cling runs exactly one activity whose `ContentState` carries every
 live pin as a `PinSnapshot`. The widget renders one pin richly, or the list
 when several are pinned (see `ClingLiveActivity` / `LivePinListView`).
 */
import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct ClingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Every pin currently on the lock screen / island, hero first. The
        /// renderers read this directly — no App Group round-trip at render
        /// time, so a roster row is as fresh as the last activity update.
        public var pins: [PinSnapshot]
        /// When the whole activity goes stale: the latest of the pins' own
        /// stale dates, capped by the system's 8 h ceiling. Each row still
        /// surfaces its own `staleDate`; this is the activity-level one.
        public var staleDate: Date?

        public init(pins: [PinSnapshot], staleDate: Date? = nil) {
            self.pins = pins
            self.staleDate = staleDate
        }
    }

    /// Schema version of the content-state shape. Bumped if the roster wire
    /// format changes, so a push server can refuse a payload it can't build.
    public var schema: Int

    public init(schema: Int = 1) {
        self.schema = schema
    }
}
#endif
