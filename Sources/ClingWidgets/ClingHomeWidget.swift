/**
 The home-screen widget: your pins, a tap from the home screen — the static
 companion to the lock-screen Live Activity.

 Reads the same App Group store the app writes (`ClingStore.loadPins`), so it
 always reflects the live board. The app nudges `WidgetCenter` on every pin
 change; the timeline also refreshes itself at the next pin's stale moment so a
 "Pinned" badge flips to "Expired" on time without the app running.

 Rows are drawn widget-native (not via the app's `listRow`) so they survive
 WidgetKit's `.vibrant` rendering — the "clear"/tinted widget style that
 desaturates everything and would turn the app's white-on-colour glyphs and
 material pills into white blobs. Taps deep-link to the pin via `cling://pin/<id>`.
 */
import SwiftUI
import WidgetKit
import iUXiOS

// MARK: - Timeline

struct HomeEntry: TimelineEntry {
    let date: Date
    let pins: [Pin]
}

struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: .now, pins: HomeEntry.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let entry = currentEntry()
        // Wake at the soonest future stale date so a pin's status flips exactly
        // when it expires; otherwise check back in an hour. WidgetCenter reloads
        // from the app cover every interactive change in between.
        let nextStale = entry.pins
            .compactMap(\.staleDate)
            .filter { $0 > entry.date }
            .min()
        let refresh = nextStale ?? entry.date.addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    /// The current board: everything not fully ended, newest first — the same
    /// rule as the app's `activePins`.
    private func currentEntry() -> HomeEntry {
        let pins = ClingStore.shared.loadPins()
            .filter { $0.status != .ended }
            .sorted { $0.createdAt > $1.createdAt }
        return HomeEntry(date: .now, pins: pins)
    }
}

// MARK: - Widget

struct ClingHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ClingKit.homeWidgetKind, provider: HomeProvider()) { entry in
            HomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Your Pins")
        .description("Your pinned things, a tap from the home screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry view

private struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HomeEntry

    var body: some View {
        content
            // The widget paints its own dark stage (ListBackdrop), so
            // pin colours read regardless of the system appearance. Force dark so
            // `.primary` / `.secondary` text resolves light instead of going
            // black-on-black when the phone is in light mode.
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        if entry.pins.isEmpty {
            EmptyHome()
        } else if family == .systemSmall && entry.pins.count > 1 {
            // More than one pin in the small tile: a notification card can only
            // hold one, so show the pins as their badges in an app-library grid.
            GlyphLibrary(pins: Array(entry.pins.prefix(9)), total: entry.pins.count)
        } else {
            ListHome(pins: Array(entry.pins.prefix(capacity)), total: entry.pins.count)
        }
    }

    /// How many notification-style cards fit per family.
    private var capacity: Int {
        switch family {
        case .systemLarge:  return 5
        case .systemMedium: return 2
        default:            return 1   // small: one card fills the tile
        }
    }
}

// MARK: - App-library grid (small, many pins)

/// The small tile when several pins are live: just their badges, tidily gridded
/// like the home-screen App Library — each a tap-through to its pin. Two columns
/// up to four pins (big badges), three beyond that, with a "+N" overflow chip.
private struct GlyphLibrary: View {
    let pins: [Pin]
    let total: Int

    private var columnCount: Int { pins.count <= 4 ? 2 : 3 }
    private var glyphSize: CGFloat { pins.count <= 4 ? 56 : 38 }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10),
                            count: columnCount)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(pins) { pin in
                Link(destination: DeepLink.pin(pin.id).url) {
                    WidgetGlyph(appearance: pin.appearance, size: glyphSize)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if total > pins.count {
                Text("+\(total - pins.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
        }
        .containerBackground(for: .widget) { ListBackdrop(pins: pins) }
    }
}

// MARK: - The board (stacked notification cards)

private struct ListHome: View {
    @Environment(\.widgetFamily) private var family
    let pins: [Pin]
    let total: Int

    private var isSmall: Bool { family == .systemSmall }
    // Only the large tile has the vertical room for a title row. On medium the
    // header plus two full cards overflow the tile and WidgetKit clips the top
    // of "Cling" and the bottom card — so drop it and let the cards breathe.
    private var showsHeader: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: isSmall ? 0 : 6) {
            if showsHeader {
                HStack {
                    Text("Cling").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(total == 1 ? "1 pinned" : "\(total) pinned")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
            }
            // Cards hold their natural height and stack from the top, like
            // notifications — never stretched to fill, so a single pin reads as
            // one card with calm space below instead of a giant void.
            ForEach(pins) { pin in
                Link(destination: DeepLink.pin(pin.id).url) {
                    PinCard(pin: pin, fills: isSmall)
                }
            }
            if total > pins.count {
                Text("+\(total - pins.count) more")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            if !isSmall { Spacer(minLength: 0) }
        }
        .containerBackground(for: .widget) { ListBackdrop(pins: pins) }
    }
}

/// One pin drawn as a notification-style card: glyph, headline (the note text /
/// label), and a status line ("Pinned until 2:12" / "Expired" / a countdown).
private struct PinCard: View {
    let pin: Pin
    /// Stretch to fill the tile (small family, one card) vs. hug content and
    /// stack like a notification (medium/large).
    var fills: Bool = false

    var body: some View {
        Group {
            if fills {
                // Small family, one card: a glyph beside the text starves the
                // headline so a word like "discord.com" breaks mid-character.
                // Stack instead — glyph up top, then text across the full width.
                VStack(alignment: .leading, spacing: 0) {
                    WidgetGlyph(appearance: pin.appearance, size: 40)
                    Spacer(minLength: 8)
                    text
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    WidgetGlyph(appearance: pin.appearance, size: 34)
                    text
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(fills ? 12 : 10)
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
        .background {
            // Lighter than before: a thin accent tint over a faint glass fill,
            // hairline accent edge — reads as a calm card, not a heavy block.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(pin.appearance.accent.color.opacity(0.15))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(pin.appearance.accent.color.opacity(0.32), lineWidth: 1))
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(pinTitle(pin))
                .font(.headline)
                .lineLimit(fills ? 3 : 1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
            PinSubtitle(pin: pin)
            WidgetStatus(pin: pin)
        }
        .fontDesign(pin.appearance.fontDesign.design)
    }
}

// MARK: - Empty

private struct EmptyHome: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pin")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing pinned")
                .font(.subheadline.weight(.medium))
            Text("Pin something in Cling")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(white: 0.10), .black],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Widget-native row (vibrant-safe)

// The home screen may re-render a widget by luminance — the "clear"/tinted
// widget style drives WidgetKit's `.vibrant` mode, which desaturates everything
// and turns white-on-colour glyphs and `.ultraThinMaterial` pills into solid
// white blobs. So the widget's rows draw their own glyph and status that adapt
// to the active rendering mode, instead of reusing the app's full-colour
// `listRow` / `ExpiryBadge`.

/// The pin's badge. In full colour it's the app's vivid glyph; in vibrant /
/// accented modes it drops to a high-contrast symbol on a faint chip so it
/// never desaturates into a featureless white square.
private struct WidgetGlyph: View {
    @Environment(\.widgetRenderingMode) private var mode
    let appearance: PinAppearance
    var size: CGFloat = 34

    var body: some View {
        if mode == .fullColor {
            PinGlyph(appearance: appearance, size: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: appearance.symbolName)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.primary))
        }
    }
}

/// The pin's live state as plain glyph + text — no material, so it survives
/// vibrant rendering. (The app list uses the warming `ExpiryBadge`; a widget
/// refreshes on its own timeline, so a static "until HH:mm" is enough.)
private struct WidgetStatus: View {
    let pin: Pin

    var body: some View {
        switch pin.status {
        case .live:
            if let staleDate = pin.staleDate, pin.isRenewable {
                stamp("Pinned until \(staleDate.formatted(date: .omitted, time: .shortened))",
                      symbol: "clock", tint: .secondary)
            } else {
                stamp("Pinned", symbol: "pin.fill", tint: pin.appearance.accent.color)
            }
        case .pending:
            stamp("Pinning…", symbol: "pin.slash", tint: .secondary)
        case .stale:
            stamp("Expired", symbol: "clock.badge.exclamationmark", tint: .orange)
        case .ended:
            EmptyView()
        }
    }

    private func stamp(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
    }
}

/// The pin's subtitle line — the secondary detail per type (a live countdown
/// for timers, the parking note, the note's web source).
private struct PinSubtitle: View {
    let pin: Pin

    var body: some View {
        switch pin.payload {
        case .timer(let t):
            Group {
                if t.endDate > .now {
                    CountdownText(from: t.startDate, until: t.endDate)
                } else {
                    Text("done")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        case .parking(let p):
            if let note = p.note {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        case .note(let n):
            // A bare-link note already shows its host as the headline, so the
            // host subtitle would just repeat it — only draw it for excerpt
            // notes (prose text + a separate source).
            if noteBareLink(n) == nil, let host = n.sourceURL?.host() {
                Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        case .decor:
            EmptyView()
        }
    }
}

/// The pin's headline, per type.
private func pinTitle(_ pin: Pin) -> String {
    switch pin.payload {
    case .note(let n):
        if n.text.isEmpty { "Note" }
        // Shared-from-web notes carry the URL as their text; a raw
        // "https://d…" makes a useless headline, so show the clean host.
        else if let url = noteBareLink(n) { prettyHost(url) }
        else { n.text }
    case .timer(let t):     t.label.isEmpty ? "Timer" : t.label
    case .parking(let p):   p.displayTitle
    case .decor(let d):     d.displayLabel ?? "Decoration"
    }
}

/// The link when a note's text is *just* a URL (a share-sheet link with no
/// excerpt), else nil — distinguishes link pins from prose notes that merely
/// carry a source.
private func noteBareLink(_ n: NotePayload) -> URL? {
    let trimmed = n.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), url.scheme != nil, url.host() != nil
    else { return nil }
    return url
}

/// A URL's host without the "www." noise — "drive.google.com" not
/// "https://www…".
private func prettyHost(_ url: URL) -> String {
    let host = url.host() ?? url.absoluteString
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

/// A calmer backdrop for the list families — a hint of the hero pin's accent so
/// the widget still wears the board's colour.
private struct ListBackdrop: View {
    let pins: [Pin]

    var body: some View {
        let hero = pins.first?.appearance.accent.color ?? Color(white: 0.2)
        ZStack {
            Color.black
            RadialGradient(colors: [hero.opacity(0.30), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 320)
        }
    }
}

// MARK: - Sample (placeholder / gallery)

extension HomeEntry {
    static var sample: [Pin] {
        [
            Pin(payload: .parking(ParkingPayload(latitude: 0, longitude: 0,
                                                 title: "Parked here", note: "Level 3, row F")),
                appearance: PinAppearance(accent: PinAppearance.sky, symbolName: "car.fill"),
                status: .live),
            Pin(payload: .timer(TimerPayload(label: "Pasta",
                                             endDate: .now.addingTimeInterval(8 * 60))),
                appearance: PinAppearance(accent: PinAppearance.ember, symbolName: "timer"),
                status: .live),
        ]
    }
}
