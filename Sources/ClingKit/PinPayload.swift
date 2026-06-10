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
    case clipboard(ClipboardPayload)

    public var typeID: PinTypeID {
        switch self {
        case .note:      .note
        case .timer:     .timer
        case .parking:   .parking
        case .clipboard: .clipboard
        }
    }
}

// MARK: - Per-type payloads

public struct NotePayload: Codable, Hashable, Sendable {
    /// Short, glanceable text. Clamped well under the ContentState budget.
    public var text: String
    /// Optional photo (a shared image, a whiteboard snap) in `PhotoStore`'s
    /// App Group directory — filename only, never bytes.
    public var photoFilename: String?

    public init(text: String, photoFilename: String? = nil) {
        self.text = String(text.prefix(500))
        self.photoFilename = photoFilename
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

    public init(label: String, startDate: Date = .now, endDate: Date) {
        self.label = String(label.prefix(100))
        self.startDate = startDate
        self.endDate = endDate
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
}

public struct ClipboardPayload: Codable, Hashable, Sendable {
    /// The pinned text, one tap from being copied back out.
    public var text: String
    /// Where it came from, when shared from a web page.
    public var sourceURL: URL?

    public init(text: String, sourceURL: URL? = nil) {
        self.text = String(text.prefix(1000))
        self.sourceURL = sourceURL
    }
}
