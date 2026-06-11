/**
 One pin, in full — led by the lock-screen stage (the pin shown the way it
 actually lives), then its primary action, type-specific extras (map for
 parking), a quiet stat strip, the appearance entry, and removal.
 */
import SwiftUI
import CoreLocation
import iUXiOS

struct PinDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pin: Pin

    var body: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                // The hero: the pin as the lock screen shows it. What you see is
                // what you pinned.
                LockScreenStage(
                    typeID: pin.typeID,
                    payload: pin.payload,
                    appearance: pin.appearance,
                    staleDate: pin.staleDate)
                    .padding(.top, 4)

                primaryAction

                typeExtras

                appearanceTile

                statStrip

                Button(role: .destructive) {
                    model.delete(pin)
                    #if canImport(UIKit)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                    dismiss()
                } label: {
                    Label("Remove pin", systemImage: "pin.slash")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassBloom)
                .glassPill(tint: .red)
                .padding(.top, 4)
            }
            .padding(UX.screenPadding)
        }
        .background {
            AmbientBackdrop(tints: [pin.appearance.accent.color,
                                    pin.appearance.accentEnd?.color].compactMap(\.self))
                .ignoresSafeArea()
        }
        .navigationTitle(PinRegistry.module(for: pin.typeID).displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Primary action

    /// The one thing you most likely opened this pin to do — front and centre,
    /// in the pin's own accent. Types without a signature action show nothing.
    @ViewBuilder private var primaryAction: some View {
        switch pin.payload {
        case .parking(let parking):
            AccentActionButton(title: "Walk me back", systemImage: "figure.walk",
                               accent: pin.appearance.accentGradient) {
                openInMaps(parking)
            }
        case .clipboard(let clip):
            AccentActionButton(title: "Copy", systemImage: "doc.on.doc",
                               accent: pin.appearance.accentGradient) {
                #if canImport(UIKit)
                UIPasteboard.general.string = clip.text
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            }
        case .note, .timer:
            EmptyView()
        }
    }

    // MARK: - Type extras

    @ViewBuilder private var typeExtras: some View {
        if case .parking(let parking) = pin.payload {
            CardSection("Where") {
                MapSnippet(
                    coordinate: CLLocationCoordinate2D(
                        latitude: parking.latitude, longitude: parking.longitude),
                    tint: pin.appearance.accent.color)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous))
                    .padding(.vertical, UX.rowVPadding)
            }
        }
    }

    // MARK: - Appearance entry

    /// A tile that previews the pin's current look — accent glyph + a one-line
    /// summary — and pushes the editor. Richer than a bare settings row.
    private var appearanceTile: some View {
        CardSection {
            NavigationLink {
                PinAppearanceEditorView(pin: pin)
            } label: {
                HStack(spacing: 12) {
                    PinGlyph(appearance: pin.appearance, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appearance")
                            .foregroundStyle(.primary)
                        Text("Color, icon, density, surface")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, UX.rowVPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stat strip

    /// Type and creation time as a quiet two-up footer — facts worth keeping,
    /// but not worth a whole card.
    private var statStrip: some View {
        HStack(spacing: 10) {
            stat("Type", PinRegistry.module(for: pin.typeID).displayName)
            stat("Created", pin.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let endDate = pin.endDate {
                stat("Ends", endDate.formatted(date: .omitted, time: .shortened))
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassTile()
    }

    private func openInMaps(_ parking: ParkingPayload) {
        let coordinate = "\(parking.latitude),\(parking.longitude)"
        if let url = URL(string: "maps://?daddr=\(coordinate)&dirflg=w") {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }
}

// MARK: - Accent action button

/// A full-width, accent-filled call to action — the pin's primary verb, in the
/// pin's own colour. Mirrors the glass language: sheen highlight, lit rim,
/// press bloom.
struct AccentActionButton: View {
    let title: String
    let systemImage: String
    let accent: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background {
                    let rr = RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous)
                    rr.fill(accent)
                        .overlay(rr.fill(
                            LinearGradient(colors: [.white.opacity(UX.Glass.sheenTopOpacity), .clear],
                                           startPoint: .top, endPoint: .bottom)))
                        .overlay(rr.strokeBorder(.white.opacity(UX.Glass.rimTopOpacity),
                                                 lineWidth: UX.Glass.rimWidth))
                }
        }
        .buttonStyle(.glassBloom)
    }
}
