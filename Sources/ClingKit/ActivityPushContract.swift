/**
 The wire contract between a server (the anti.ltd Worker) and Cling for pushing
 Live Activities over APNs. One source of truth for the strings both ends must
 agree on, plus a reference encoder that emits the EXACT `content-state` JSON the
 system will decode — so the server side can be written against real output
 instead of guesswork about Swift's Codable synthesis.

 See docs/PUSH-TO-START.md for the full APNs request (headers + body shape).
 */
import Foundation

public enum ActivityPushContract {
    /// The `attributes-type` value in a push-to-start payload — must equal the
    /// `ActivityAttributes` type name exactly, or iOS drops the push.
    public static let attributesTypeName = "ClingActivityAttributes"

    /// APNs `apns-topic` for Live Activity pushes: "<bundleid>.push-type.liveactivity".
    public static let apnsTopic = "ltd.anti.cling.push-type.liveactivity"

    /// APNs `apns-push-type` header value.
    public static let pushTypeHeader = "liveactivity"

    /// Values for `aps.event`.
    public enum Event {
        public static let start = "start"
        public static let update = "update"
        public static let end = "end"
    }

    /// Date strategy for every `Date` inside `content-state` (and `attributes`):
    /// **seconds since 2001 (`timeIntervalSinceReferenceDate`), as a NUMBER.**
    ///
    /// ActivityKit decodes a pushed `content-state` with its own internal coder,
    /// which expects each `Date` as a number (an ISO-8601 *string* throws a
    /// `typeMismatch` → the whole content-state is rejected and the activity spins).
    /// That coder is Swift's DEFAULT `Date` Codable = `timeIntervalSinceReference
    /// Date` (2001 base), NOT Unix-1970 — device-confirmed: a 1970-based number
    /// made the live match clock anchor render ~31 years off (`271751:06:54`).
    /// Both ends now emit 2001-based seconds; the Worker's `csDate()` matches.
    /// (The APNs-header `timestamp`/`stale-date` are a separate domain — Unix-1970.)
    nonisolated(unsafe) public static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

#if canImport(ActivityKit)
import ActivityKit

public extension ActivityPushContract {
    /// JSONEncoder configured exactly as the reference output assumes. Use this
    /// for both the helpers below and any tests that snapshot the wire shape.
    static func referenceEncoder(pretty: Bool = true) -> JSONEncoder {
        let e = JSONEncoder()
        // Seconds since 2001 (reference date), NOT .secondsSince1970 and NOT
        // .iso8601: matches ActivityKit's native content-state Date coder. A 1970
        // base renders the live clock ~31 years off; a string spins the activity.
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.timeIntervalSinceReferenceDate)
        }
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return e
    }

    /// The wire ceiling ActivityKit enforces on a content-state is ~4 KB, and it
    /// SILENTLY drops any update/start/push over it — the activity then freezes on
    /// stale/empty content (an empty lock-screen card) while the app still shows
    /// the full roster. Stay a margin under, leaving room for the system's framing.
    static let contentStateBudget = 3_800

    /// Trim a roster to fit `contentStateBudget`: drop the least-important (tail)
    /// snapshots until the encoded content-state fits. Callers pass snapshots in
    /// priority order (hero / live-sport first), so trimming sheds the rides-along
    /// pins first. Never returns empty when given pins — the hero always survives.
    static func fitToBudget(_ snapshots: [PinSnapshot]) -> [PinSnapshot] {
        guard !snapshots.isEmpty else { return snapshots }
        let encoder = referenceEncoder(pretty: false)
        func size(_ pins: [PinSnapshot]) -> Int {
            let state = ClingActivityAttributes.ContentState(pins: pins, staleDate: nil)
            return (try? encoder.encode(state))?.count ?? .max
        }
        var pins = snapshots
        while pins.count > 1, size(pins) > contentStateBudget {
            pins.removeLast()
        }
        return pins
    }

    /// The roster `content-state` object, as a JSON string — paste-able into a
    /// push payload's `aps.content-state`. The canonical reference for the
    /// server: the Worker mutates only the sport elements inside `pins[]` (by
    /// matching sourceID) and re-pushes the whole object, so it never has to
    /// reproduce a `PinSnapshot` from scratch.
    static func referenceContentStateJSON(for snapshots: [PinSnapshot], staleDate: Date) -> String {
        let state = ClingActivityAttributes.ContentState(pins: snapshots, staleDate: staleDate)
        let data = (try? referenceEncoder().encode(state)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The `attributes` object, as a JSON string — paste-able into a push
    /// payload's `aps.attributes` (start events only). The roster attributes
    /// carry only a schema version.
    static func referenceAttributesJSON() -> String {
        let attributes = ClingActivityAttributes()
        let data = (try? referenceEncoder().encode(attributes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
