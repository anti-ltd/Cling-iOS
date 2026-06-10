/**
 One pin, in full: the content card (the module's lock-screen view — the
 detail IS the preview), type-specific extras (map for parking), timestamps,
 and the remove action. Appearance editing arrives with the customization
 phase.
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
                // The pin as the lock screen shows it — what you see is what
                // you pinned.
                CardSection("On your lock screen") {
                    PinRegistry.module(for: pin.typeID)
                        .lockScreen(PinRenderContext(
                            pinID: pin.id,
                            payload: pin.payload,
                            appearance: pin.appearance))
                        .padding(.vertical, UX.rowVPadding)
                }

                typeExtras

                CardSection {
                    NavRow("Appearance", subtitle: "Color, icon, density, surface",
                           systemImage: "paintbrush.fill") {
                        PinAppearanceEditorView(pin: pin)
                    }
                }

                CardSection("Details") {
                    detailRow("Type", value: PinRegistry.module(for: pin.typeID).displayName)
                    Divider()
                    detailRow("Created", value: pin.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let endDate = pin.endDate {
                        Divider()
                        detailRow("Ends", value: endDate.formatted(date: .omitted, time: .shortened))
                    }
                }

                Button(role: .destructive) {
                    model.delete(pin)
                    #if canImport(UIKit)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                    dismiss()
                } label: {
                    Label("Remove pin", systemImage: "pin.slash")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassBloom)
                .glassTile(tint: .red)
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

    @ViewBuilder private var typeExtras: some View {
        if case .parking(let parking) = pin.payload {
            CardSection("Where") {
                MapSnippet(
                    coordinate: CLLocationCoordinate2D(
                        latitude: parking.latitude, longitude: parking.longitude),
                    tint: pin.appearance.accent.color)
                    .frame(height: 160)
                    .padding(.vertical, UX.rowVPadding)
                Button {
                    openInMaps(parking)
                } label: {
                    Label("Walk me back", systemImage: "figure.walk")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassBloom)
            }
        }
        if case .clipboard(let clip) = pin.payload {
            CardSection {
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = clip.text
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassBloom)
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
        .padding(.vertical, 8)
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
