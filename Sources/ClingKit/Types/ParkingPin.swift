/**
 The Parking pin: a location, an optional note ("level 3, row F"), an optional
 photo. The Live Activity shows the note + photo thumbnail; the map snippet
 and directions live in the app's detail screen (widget views can't do async
 map snapshotting).
 */
import SwiftUI
import iUXiOS
#if canImport(UIKit)
import UIKit
import CoreText
#endif

@MainActor
public enum ParkingPinModule: PinModule {
    public static let typeID: PinTypeID = .parking
    public static let displayName = "Parking"
    public static let systemImage = "car.fill"
    public static let symbolChoices = [
        "car.fill", "parkingsign", "bicycle", "scooter",
        "bus.fill", "tram.fill", "figure.walk",
    ]

    private static func payload(_ payload: PinPayload) -> ParkingPayload? {
        if case .parking(let parking) = payload { return parking }
        return nil
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(ParkingQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        let parking = payload(pin.payload)
        return AnyView(
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(parking?.displayTitle ?? "Parked")
                        .font(.body)
                    if let note = parking?.note {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let parking, let filename = parking.photoFilename {
                    thumb(filename, size: 40)
                }
            }
        )
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        guard let parking = payload(ctx.payload) else { return AnyView(EmptyView()) }
        let compact = ctx.density == .compact
        return AnyView(
            HStack(spacing: 12) {
                PinGlyph(appearance: ctx.appearance,
                         size: compact ? 30 : 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(parking.displayTitle)
                        .font(compact ? .subheadline : .body.weight(.medium))
                    if let note = parking.note {
                        Text(note)
                            .font(compact ? .caption : .subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(compact ? 1 : 2)
                    }
                }
                Spacer(minLength: 0)
                if let filename = parking.photoFilename {
                    thumb(filename, size: compact ? 36 : 48)
                }
            }
        )
    }

    public static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView {
        guard let parking = payload(ctx.payload) else { return AnyView(EmptyView()) }
        // Title only. The note lives in the bottom region — the center region
        // has a fixed height that clips a second text line.
        return AnyView(
            Text(parking.displayTitle)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        // Inset from the island's rounded corner — otherwise the corner curve
        // clips the badge's top-left.
        AnyView(
            PinGlyph(appearance: ctx.appearance, size: 40)
                .padding(.leading, 4)
                .padding(.top, 2)
        )
    }

    /// The actionable bit: a Link to Apple Maps walking directions. A Link
    /// inside a Dynamic Island region overrides the island's `.widgetURL`
    /// (which opens the app), so this tap goes straight to Maps instead.
    public static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView? {
        guard let parking = payload(ctx.payload) else { return nil }
        let provider = ClingStore.shared.loadSettings().mapProvider
        return AnyView(
            VStack(spacing: 6) {
                if let note = parking.note {
#if canImport(UIKit)
                    fractionText(note, base: designed(.subheadline, ctx.appearance.fontDesign.design))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
#else
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
#endif
                }
                Link(destination: parking.walkingDirectionsURL(provider: provider)) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Walk")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(ctx.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
        )
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let parking = payload(ctx.payload), let filename = parking.photoFilename else {
            return AnyView(EmptyView())
        }
        return AnyView(thumb(filename, size: 28))
    }

    /// The row carries its own Walk `Link`, so the roster must not wrap it in an
    /// outer link — nested interactive controls blank the whole Live Activity.
    public static let liveRowHasInlineAction = true

    public static func liveRow(_ ctx: PinRenderContext) -> AnyView {
        guard let parking = payload(ctx.payload) else { return AnyView(EmptyView()) }
        let provider = ClingStore.shared.loadSettings().mapProvider
        return AnyView(
            HStack(spacing: 10) {
                PinGlyph(appearance: ctx.appearance, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(parking.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let note = parking.note {
#if canImport(UIKit)
                        fractionText(note, base: designed(.caption2, ctx.appearance.fontDesign.design))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
#else
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
#endif
                    }
                }
                Spacer(minLength: 8)
                Link(destination: parking.walkingDirectionsURL(provider: provider)) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 32)
                        .background(ctx.accent, in: Capsule())
                }
            }
        )
    }

    public static func diCompactLeading(_ ctx: PinRenderContext) -> AnyView {
        AnyView(
            Image(systemName: ctx.appearance.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ctx.accent)
        )
    }

    public static func diCompactTrailing(_ ctx: PinRenderContext) -> AnyView {
        // If they told us where they parked, show that instead of a bare "P".
        let note = payload(ctx.payload)?.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note, !note.isEmpty {
#if canImport(UIKit)
            return AnyView(
                fractionText(note, base: .systemFont(ofSize: 13, weight: .semibold))
                    .foregroundStyle(ctx.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            )
#else
            return AnyView(
                Text(note)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ctx.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            )
#endif
        }
        return AnyView(
            Image(systemName: "parkingsign")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ctx.accent)
        )
    }

#if canImport(UIKit)
    /// Turns ASCII fractions ("3/4") into true diagonal fraction glyphs — a
    /// small numerator over a small denominator — so they read tidy and don't
    /// inflate the line height with full-size digits.
    private static func fractioned(_ base: UIFont) -> Font {
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kFractionsType,
                UIFontDescriptor.FeatureKey.selector: kDiagonalFractionsSelector,
            ]]
        ])
        return Font(UIFont(descriptor: desc, size: base.pointSize))
    }

    /// Builds a `Text` where only fraction tokens (`3/4`) get the diagonal
    /// fraction font; everything else — including a leading whole number like
    /// the `9` in `9 3/4` — stays full size in `base`.
    private static func fractionText(_ s: String, base: UIFont) -> Text {
        let normal = Font(base)
        let frac = fractioned(base)
        let ns = s as NSString
        let matches = (try? NSRegularExpression(pattern: "\\d+/\\d+"))?
            .matches(in: s, range: NSRange(location: 0, length: ns.length)) ?? []
        guard !matches.isEmpty else { return Text(s).font(normal) }

        var result = Text("")
        var idx = 0
        for m in matches {
            if m.range.location > idx {
                let pre = ns.substring(with: NSRange(location: idx, length: m.range.location - idx))
                result = result + Text(pre).font(normal)
            }
            result = result + Text(ns.substring(with: m.range)).font(frac)
            idx = m.range.location + m.range.length
        }
        if idx < ns.length {
            result = result + Text(ns.substring(from: idx)).font(normal)
        }
        return result
    }

    /// A dynamic-type font for `style`, carrying the pin's font design so the
    /// fraction note matches the rest of the activity (rounded/serif/etc.).
    private static func designed(_ style: UIFont.TextStyle, _ design: Font.Design?) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let system: UIFontDescriptor.SystemDesign
        switch design {
        case .rounded:    system = .rounded
        case .serif:      system = .serif
        case .monospaced: system = .monospaced
        default:          system = .default
        }
        guard let desc = base.fontDescriptor.withDesign(system) else { return base }
        return UIFont(descriptor: desc, size: 0)
    }
#endif

    /// Loads the photo from the shared container — the widget process can,
    /// because both sides sit in the App Group.
    @ViewBuilder private static func thumb(_ filename: String, size: CGFloat) -> some View {
        #if canImport(UIKit)
        GlassThumb(
            image: PhotoStore.shared.loadImage(filename).map(Image.init(uiImage:)),
            size: CGSize(width: size, height: size),
            placeholderSymbol: "car.fill")
        #else
        GlassThumb(image: nil, size: CGSize(width: size, height: size), placeholderSymbol: "car.fill")
        #endif
    }
}

/// The location itself comes from the composer's one-shot fix (or the photo
/// picker), wired app-side — this form holds the human details.
private struct ParkingQuickAddForm: View {
    @Binding var draft: PinDraft
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextFieldRow(prompt: "Parked here — or call it anything", text: $draft.title)
                .focused($focused)
            TextFieldRow(prompt: "Level, row, anything to remember (optional)", text: $draft.parkingNote)
            HStack(spacing: 6) {
                Image(systemName: draft.latitude != nil ? "location.fill" : "location")
                Text(draft.latitude != nil ? "Location captured" : "Capturing location…")
            }
            .font(.caption)
            .foregroundStyle(draft.latitude != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.bottom, 10)
        }
    }
}
