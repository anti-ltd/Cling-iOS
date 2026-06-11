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
        if entry.pins.isEmpty {
            EmptyHome()
        } else if family == .systemSmall {
            SmallHome(pin: entry.pins[0], overflow: entry.pins.count - 1)
        } else {
            ListHome(pins: Array(entry.pins.prefix(family == .systemLarge ? 5 : 3)),
                     total: entry.pins.count)
        }
    }
}

// MARK: - Small (one pin, hero)

private struct SmallHome: View {
    let pin: Pin
    /// How many other pins aren't shown.
    let overflow: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetGlyph(appearance: pin.appearance, size: 42)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(pinTitle(pin))
                    .font(.headline)
                    .lineLimit(2)
                PinSubtitle(pin: pin)
            }
            .fontDesign(pin.appearance.fontDesign.design)
            HStack(spacing: 6) {
                WidgetStatus(pin: pin)
                Spacer(minLength: 0)
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { AccentWash(appearance: pin.appearance) }
        .widgetURL(DeepLink.pin(pin.id).url)
    }
}

// MARK: - Medium / Large (a list)

private struct ListHome: View {
    let pins: [Pin]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cling")
                    .font(.headline)
                Spacer()
                Text(total == 1 ? "1 pinned" : "\(total) pinned")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ForEach(pins) { pin in
                Link(destination: DeepLink.pin(pin.id).url) {
                    WidgetPinRow(pin: pin)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(pin.appearance.accent.color.opacity(0.35), lineWidth: 1))
                        }
                }
            }
            if total > pins.count {
                Text("+\(total - pins.count) more")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { ListBackdrop(pins: pins) }
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

/// One pin as a widget row: glyph, title + subtitle, trailing status.
private struct WidgetPinRow: View {
    let pin: Pin

    var body: some View {
        HStack(spacing: 10) {
            WidgetGlyph(appearance: pin.appearance, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(pinTitle(pin))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                PinSubtitle(pin: pin)
            }
            Spacer(minLength: 6)
            WidgetStatus(pin: pin)
        }
        .fontDesign(pin.appearance.fontDesign.design)
    }
}

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
                stamp("until \(staleDate.formatted(date: .omitted, time: .shortened))",
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
        }
        .foregroundStyle(tint)
    }
}

/// The pin's subtitle line — the secondary detail per type (a live countdown
/// for timers, the parking note, the clipboard source).
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
        case .clipboard(let c):
            if let host = c.sourceURL?.host() {
                Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        case .note:
            EmptyView()
        }
    }
}

/// The pin's headline, per type.
private func pinTitle(_ pin: Pin) -> String {
    switch pin.payload {
    case .note(let n):      n.text.isEmpty ? "Note" : n.text
    case .timer(let t):     t.label.isEmpty ? "Timer" : t.label
    case .parking(let p):   p.displayTitle
    case .clipboard(let c): c.text.isEmpty ? "Clipboard" : c.text
    }
}

/// A pin-accent wash for the small widget — the pool of colour pinned at the
/// top, sinking to near-black, echoing the app's lock-screen stage.
private struct AccentWash: View {
    let appearance: PinAppearance

    var body: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [appearance.accent.color.opacity(0.45),
                         (appearance.accentEnd ?? appearance.accent).color.opacity(0.18),
                         .black],
                startPoint: .topLeading, endPoint: .bottom)
        }
    }
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
