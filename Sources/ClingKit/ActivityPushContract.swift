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

    /// Date strategy for every `Date` inside `content-state` (and `attributes`).
    /// ISO-8601 with fractional seconds — matches what we tell the server to
    /// send and what the reference encoder below produces. NOTE: Apple does not
    /// publicly pin ActivityKit's content-state date strategy; this pairing is
    /// internally consistent but MUST be confirmed on device (per the project's
    /// no-simulator-build rule) before the server goes live.
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
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return e
    }

    /// The `content-state` object for a pin, as a JSON string — paste-able into
    /// a push payload's `aps.content-state`. The canonical reference for the
    /// server: print it for a sample pin, mirror the shape in the Worker.
    static func referenceContentStateJSON(for pin: Pin, staleDate: Date) -> String {
        let state = ClingActivityAttributes.ContentState(
            payload: pin.payload, appearance: pin.appearance, staleDate: staleDate)
        let data = (try? referenceEncoder().encode(state)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The `attributes` object for a pin, as a JSON string — paste-able into a
    /// push payload's `aps.attributes` (start events only).
    static func referenceAttributesJSON(for pin: Pin) -> String {
        let attributes = ClingActivityAttributes(pinID: pin.id, typeID: pin.typeID)
        let data = (try? referenceEncoder().encode(attributes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
