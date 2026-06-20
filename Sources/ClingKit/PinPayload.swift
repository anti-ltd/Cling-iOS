/**
 `PinPayload`: the typed content of a pin, one case per pin type.

 ActivityKit binds each Live Activity configuration to ONE concrete
 `ActivityAttributes` type, so heterogeneous pins travel as this Codable enum
 and fan out to per-type renderers at the view layer (see `PinModule`).

 Size discipline: the encoded payload rides in the activity's `ContentState`,
 which iOS caps around 4KB. Text fields are clamped at creation and images are
 NEVER embedded — only filenames pointing into the App Group container.
 */
import Foundation

public enum PinPayload: Codable, Hashable, Sendable {
    case note(NotePayload)
    case timer(TimerPayload)
    case parking(ParkingPayload)
    case decor(DecorPayload)

    public var typeID: PinTypeID {
        switch self {
        case .note:      .note
        case .timer:     .timer
        case .parking:   .parking
        case .decor:     .decor
        }
    }
}

/// A purely decorative pin: no functional content, just a presence in the
/// Dynamic Island wearing the house style. The glyph and accent come from the
/// pin's `PinAppearance`; this payload only carries an optional caption.
public struct DecorPayload: Codable, Hashable, Sendable {
    /// A short caption beside the glyph ("On air", a word, an emoji). Empty or
    /// nil renders the glyph alone.
    public var label: String?

    public init(label: String? = nil) {
        self.label = label.map { String($0.prefix(40)) }
    }

    /// The caption when there's one worth drawing.
    public var displayLabel: String? {
        guard let label, !label.isEmpty else { return nil }
        return label
    }
}

// MARK: - Per-type payloads

public struct NotePayload: Codable, Hashable, Sendable {
    /// Glanceable text — anything you want held in view, including pasted
    /// snippets. Clamped well under the ContentState budget.
    public var text: String
    /// Optional photo (a shared image, a whiteboard snap) in `PhotoStore`'s
    /// App Group directory — filename only, never bytes.
    public var photoFilename: String?
    /// Where the text came from, when shared from a web page — provenance for
    /// notes pinned via the share sheet.
    public var sourceURL: URL?

    public init(text: String, photoFilename: String? = nil, sourceURL: URL? = nil) {
        self.text = String(text.prefix(1000))
        self.photoFilename = photoFilename
        self.sourceURL = sourceURL
    }
}

/// How a timer pin draws its countdown on the lock-screen card (and, where it
/// fits, the expanded island). The numbers always tick client-side via
/// `Text(timerInterval:)`/`ProgressView(timerInterval:)`; this only picks the
/// shape wrapped around them.
public enum CountdownStyle: String, Codable, Sendable, Hashable, CaseIterable {
    /// Just the numerals — the quietest, most glanceable.
    case text
    /// Numerals beside a circular progress ring that empties as time runs out.
    case ring
    /// Numerals over a thin horizontal bar that drains left-to-right.
    case bar
    /// Numerals over the whole card, its accent fill receding as time runs out.
    case fill

    public var label: String {
        switch self {
        case .text: "Text"
        case .ring: "Ring"
        case .bar:  "Bar"
        case .fill: "Fill"
        }
    }
}

public struct TimerPayload: Codable, Hashable, Sendable {
    /// What the countdown is for ("Pasta", "Rest", "Meeting").
    public var label: String
    /// When the countdown started — kept so progress reads true after a
    /// relaunch or re-arm rather than resetting visually.
    public var startDate: Date
    /// The moment the countdown hits zero.
    public var endDate: Date
    /// How the countdown renders. Per-pin so different timers can read
    /// differently (a ring for a workout, plain text for a meeting).
    public var style: CountdownStyle

    public init(label: String, startDate: Date = .now, endDate: Date, style: CountdownStyle = .text) {
        self.label = String(label.prefix(100))
        self.startDate = startDate
        self.endDate = endDate
        self.style = style
    }

    // Forward-compatible decoding: pins stored before `style` existed lack the
    // key, so fall back to `.text` rather than failing the whole store.
    private enum CodingKeys: String, CodingKey {
        case label, startDate, endDate, style
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        style = (try? c.decode(CountdownStyle.self, forKey: .style)) ?? .text
    }
}

public struct ParkingPayload: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// The headline on the activity — defaults to "Parked here" when nil, but
    /// it's the user's pin: "Train", "Bike's locked up", whatever.
    public var title: String?
    /// "Level 3, row F" — the detail GPS can't give you.
    public var note: String?
    /// Filename of a photo in `PhotoStore`'s App Group directory. A name, not
    /// bytes — the widget process shares the container and loads it itself.
    public var photoFilename: String?

    public init(
        latitude: Double,
        longitude: Double,
        title: String? = nil,
        note: String? = nil,
        photoFilename: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.title = title.map { String($0.prefix(100)) }
        self.note = note.map { String($0.prefix(200)) }
        self.photoFilename = photoFilename
    }

    /// What the renderers show — the user's title, or the default.
    public var displayTitle: String { title ?? "Parked here" }

    /// Walking directions to the spot, in the user's chosen maps app. Built
    /// here (not async) so the widget process can hand straight off to Maps.
    public func walkingDirectionsURL(provider: MapProvider) -> URL {
        provider.walkingDirectionsURL(latitude: latitude, longitude: longitude)
    }
}
