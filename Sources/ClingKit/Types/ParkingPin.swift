/**
 The Parking pin: a location, an optional note ("level 3, row F"), an optional
 photo. The Live Activity shows the note + photo thumbnail; the map snippet
 and directions live in the app's detail screen (widget views can't do async
 map snapshotting).
 */
import SwiftUI
import iUXiOS

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
                PinGlyph(appearance: pin.appearance)
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
        return AnyView(
            VStack(spacing: 1) {
                Text(parking.displayTitle)
                    .font(.subheadline.weight(.medium))
                if let note = parking.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        AnyView(PinGlyph(appearance: ctx.appearance, size: 28))
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let parking = payload(ctx.payload), let filename = parking.photoFilename else {
            return AnyView(EmptyView())
        }
        return AnyView(thumb(filename, size: 28))
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
            return AnyView(
                Text(note)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ctx.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            )
        }
        return AnyView(
            Image(systemName: "parkingsign")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ctx.accent)
        )
    }

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
