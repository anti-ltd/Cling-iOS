/**
 The inbound "pin this for me" API. Any other app — Clink sending a note, a
 Shortcut, a script — hands Cling a pin to create and activate immediately by
 opening a `cling://create/<type>?…` URL.

 Two halves live here on purpose:

 - `init?(url:)` is the RECEIVING side, compiled into the app, that turns an
   incoming URL into a `PinPayload` ready for `PinService`.
 - The `.note(…)`/`.timer(…)`/`.parking(…)` builders + `.url` are the SENDING
   side, a type-safe way for a client to construct the same URL. They share one
   grammar so the two ends can never drift — copy this file into the caller
   (it's pure Foundation) and you have a checked client SDK for free.

 Grammar is human-readable, not an opaque blob, so it's equally callable from a
 Shortcut's "Open URL" action with no code:

   cling://create/note?text=Pick%20up%20milk&from=clink
   cling://create/timer?label=Pasta&duration=600&style=ring
   cling://create/parking?lat=51.5&lng=-0.12&title=Garage&note=Level%203

 Everything past the type is optional except each type's required fields (note
 text; timer label+when; parking lat+lng). Unknown query items are ignored so
 the grammar can grow without breaking older callers.
 */
import Foundation

public struct ClingCreateRequest: Equatable, Sendable {
    /// The pin to create — already validated and clamped by `PinPayload`'s inits.
    public var payload: PinPayload
    /// Who sent it ("clink", a bundle id, a Shortcut name) — attribution for
    /// logging and, later, surfacing "via Clink" on the pin. Optional.
    public var source: String?
    /// x-callback-url success hook. After the pin is live Cling opens this URL
    /// with `clingPinID` appended, letting the caller confirm and deep-link
    /// back to the new pin. Optional.
    public var xSuccess: URL?

    public init(payload: PinPayload, source: String? = nil, xSuccess: URL? = nil) {
        self.payload = payload
        self.source = source
        self.xSuccess = xSuccess
    }

    /// The host that marks a create URL, vs. the navigation hosts in `DeepLink`.
    static let host = "create"

    // MARK: - Receiving: URL -> request

    public init?(url: URL) {
        guard url.scheme == ClingKit.urlScheme,
              url.host == Self.host else { return nil }

        // cling://create/<type> — the type is the single path component.
        let typeRaw = url.pathComponents.first { $0 != "/" } ?? ""
        guard let type = PinTypeID(rawValue: typeRaw) else { return nil }

        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        func value(_ name: String) -> String? {
            q.first { $0.name == name }?.value?.nonEmpty
        }

        let payload: PinPayload
        switch type {
        case .note:
            guard let text = value("text") else { return nil }
            payload = .note(NotePayload(
                text: text,
                sourceURL: value("sourceURL").flatMap(URL.init(string:))))

        case .timer:
            guard let label = value("label") else { return nil }
            // `end` (ISO-8601) wins; else `duration` seconds from now. One of
            // the two is required — a countdown needs a finish line.
            let end: Date
            if let iso = value("end"), let d = Self.iso.date(from: iso) {
                end = d
            } else if let secs = value("duration").flatMap(Double.init), secs > 0 {
                end = Date(timeIntervalSinceNow: secs)
            } else {
                return nil
            }
            let style = value("style").flatMap(CountdownStyle.init(rawValue:)) ?? .text
            payload = .timer(TimerPayload(label: label, endDate: end, style: style))

        case .parking:
            guard let lat = value("lat").flatMap(Double.init),
                  let lng = value("lng").flatMap(Double.init) else { return nil }
            payload = .parking(ParkingPayload(
                latitude: lat,
                longitude: lng,
                title: value("title"),
                note: value("note")))

        case .decor:
            // No required fields — a decoration is glyph + optional caption.
            payload = .decor(DecorPayload(label: value("label")))
        }

        self.init(
            payload: payload,
            source: value("from"),
            xSuccess: value("x-success").flatMap(URL.init(string:)))
    }

    // MARK: - Sending: request -> URL

    public var url: URL {
        var c = URLComponents()
        c.scheme = ClingKit.urlScheme
        c.host = Self.host
        c.path = "/\(payload.typeID.rawValue)"

        var items: [URLQueryItem] = []
        switch payload {
        case .note(let n):
            items.append(.init(name: "text", value: n.text))
            if let s = n.sourceURL { items.append(.init(name: "sourceURL", value: s.absoluteString)) }
        case .timer(let t):
            items.append(.init(name: "label", value: t.label))
            items.append(.init(name: "end", value: Self.iso.string(from: t.endDate)))
            items.append(.init(name: "style", value: t.style.rawValue))
        case .parking(let p):
            items.append(.init(name: "lat", value: String(p.latitude)))
            items.append(.init(name: "lng", value: String(p.longitude)))
            if let t = p.title { items.append(.init(name: "title", value: t)) }
            if let n = p.note { items.append(.init(name: "note", value: n)) }
        case .decor(let d):
            if let l = d.label { items.append(.init(name: "label", value: l)) }
        }
        if let source { items.append(.init(name: "from", value: source)) }
        if let xSuccess { items.append(.init(name: "x-success", value: xSuccess.absoluteString)) }

        c.queryItems = items
        return c.url!
    }

    // MARK: - Client builders (type-safe sending side)

    public static func note(
        _ text: String,
        sourceURL: URL? = nil,
        from source: String? = nil,
        xSuccess: URL? = nil
    ) -> ClingCreateRequest {
        ClingCreateRequest(
            payload: .note(NotePayload(text: text, sourceURL: sourceURL)),
            source: source, xSuccess: xSuccess)
    }

    public static func timer(
        label: String,
        duration: TimeInterval,
        style: CountdownStyle = .text,
        from source: String? = nil,
        xSuccess: URL? = nil
    ) -> ClingCreateRequest {
        ClingCreateRequest(
            payload: .timer(TimerPayload(
                label: label, endDate: Date(timeIntervalSinceNow: duration), style: style)),
            source: source, xSuccess: xSuccess)
    }

    public static func parking(
        latitude: Double,
        longitude: Double,
        title: String? = nil,
        note: String? = nil,
        from source: String? = nil,
        xSuccess: URL? = nil
    ) -> ClingCreateRequest {
        ClingCreateRequest(
            payload: .parking(ParkingPayload(
                latitude: latitude, longitude: longitude, title: title, note: note)),
            source: source, xSuccess: xSuccess)
    }

    /// Build the success callback Cling should open, tagging it with the id of
    /// the pin it just created. Nil when the caller supplied no `x-success`.
    public func successCallback(pinID: UUID) -> URL? {
        guard let xSuccess,
              var c = URLComponents(url: xSuccess, resolvingAgainstBaseURL: false)
        else { return nil }
        c.queryItems = (c.queryItems ?? []) + [.init(name: "clingPinID", value: pinID.uuidString)]
        return c.url
    }

    /// ISO-8601 with fractional seconds — the wire format for absolute dates.
    /// `ISO8601DateFormatter` is thread-safe for parse/format but not marked
    /// `Sendable`, hence the explicit opt-out.
    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

private extension String {
    /// Treat empty query values as absent — `?text=` is not a note.
    var nonEmpty: String? { isEmpty ? nil : self }
}
