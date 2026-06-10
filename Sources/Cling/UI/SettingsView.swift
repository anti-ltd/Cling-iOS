/**
 App settings: the renewal nudge, the app's own accent, and per-type default
 appearances (each opens the same editor the pin detail uses, previewing a
 sample payload).
 */
import SwiftUI
import iUXiOS

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Pins") {
                    ToggleRow(
                        "Renewal reminders",
                        subtitle: "iOS unpins everything after 8 hours. Get a nudge shortly before, so a tap keeps it alive.",
                        isOn: $model.settings.renewalRemindersEnabled)
                }

                CardSection("App color") {
                    HStack(spacing: 12) {
                        ForEach(PinAppearance.accentPresets, id: \.self) { swatch in
                            Button {
                                withAnimation(UX.Motion.morph) {
                                    model.settings.appAccent = swatch
                                }
                            } label: {
                                Circle()
                                    .fill(swatch.color)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if model.settings.appAccent == swatch {
                                            Circle().strokeBorder(.white, lineWidth: 2)
                                                .padding(2)
                                        }
                                    }
                            }
                            .buttonStyle(.glassBloom)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, UX.rowVPadding)
                }

                CardSection("New pins look like") {
                    ForEach(Array(PinTypeID.allCases.enumerated()), id: \.element) { index, typeID in
                        if index > 0 { Divider() }
                        defaultAppearanceRow(typeID)
                    }
                }
            }
            .padding(UX.screenPadding)
        }
        .background {
            AmbientBackdrop(tint: model.settings.appAccent.color)
                .ignoresSafeArea()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func defaultAppearanceRow(_ typeID: PinTypeID) -> some View {
        let module = PinRegistry.module(for: typeID)
        let appearance = model.settings.defaultAppearance(for: typeID)
        NavRow(module.displayName, systemImage: appearance.symbolName) {
            DefaultAppearanceEditor(typeID: typeID)
        }
    }
}

/// Edits the default appearance new pins of a type inherit.
private struct DefaultAppearanceEditor: View {
    @Environment(AppModel.self) private var model
    let typeID: PinTypeID

    var body: some View {
        ScrollView {
            AppearanceEditor(
                typeID: typeID,
                previewPayload: SamplePayloads.payload(for: typeID),
                appearance: Binding(
                    get: { model.settings.defaultAppearance(for: typeID) },
                    set: { model.settings.defaultAppearances[typeID] = $0 }))
                .padding(UX.screenPadding)
        }
        .background {
            AmbientBackdrop(tint: model.settings.appAccent.color)
                .ignoresSafeArea()
        }
        .navigationTitle(PinRegistry.module(for: typeID).displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
