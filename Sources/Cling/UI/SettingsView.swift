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

                CardSection("Directions") {
                    HStack(spacing: 8) {
                        ForEach(MapProvider.allCases, id: \.self) { provider in
                            let selected = model.settings.mapProvider == provider
                            Button {
                                withAnimation(UX.Motion.morph) {
                                    model.settings.mapProvider = provider
                                }
                            } label: {
                                Text(provider.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(
                                        selected ? AnyShapeStyle(model.settings.appAccent.color)
                                                 : AnyShapeStyle(.quaternary),
                                        in: Capsule())
                            }
                            .buttonStyle(.glassBloom)
                        }
                    }
                    .padding(.vertical, UX.rowVPadding)
                }

                CardSection("Dynamic Island style") {
                    NavRow("Surface, type & border", systemImage: "wand.and.stars") {
                        GlobalStyleEditor()
                    }
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
                    set: { model.settings.defaultAppearances[typeID] = $0 }),
                globalStyle: model.settings.globalStyle)
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

/// The one place the shared look lives: surface, type, density and border for
/// every pin and the Dynamic Island. The preview is the real renderer; tuning a
/// chip re-dresses all live pins instantly (AppModel restyles on change). Accent
/// and glyph stay per-type — those live under "New pins look like".
private struct GlobalStyleEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Preview") {
                    PinPreviewCard(
                        typeID: .note,
                        payload: SamplePayloads.payload(for: .note),
                        appearance: model.settings.defaultAppearance(for: .note),
                        globalStyle: model.settings.globalStyle)
                        .padding(.vertical, UX.rowVPadding)
                }

                CardSection("Surface & type") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Density")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        OptionChips(
                            options: [("Compact", LayoutDensity.compact), ("Regular", .regular)],
                            selection: $model.settings.globalStyle.density)
                        Text("Surface")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        OptionChips(
                            options: [("Glass", PinStyle.glass), ("Solid", .solid), ("Outline", .outline)],
                            selection: $model.settings.globalStyle.style)
                        Text("Type")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        OptionChips(
                            options: [
                                ("Standard", PinFontDesign.standard), ("Rounded", .rounded),
                                ("Serif", .serif), ("Mono", .mono),
                            ],
                            selection: $model.settings.globalStyle.fontDesign)
                        Text("Border")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        OptionChips(
                            options: [("None", PinBorder.none), ("Hairline", .hairline), ("Accent", .accent)],
                            selection: $model.settings.globalStyle.border)
                    }
                    .padding(.vertical, UX.rowVPadding)
                }
            }
            .padding(UX.screenPadding)
        }
        .background {
            AmbientBackdrop(tint: model.settings.appAccent.color)
                .ignoresSafeArea()
        }
        .navigationTitle("Dynamic Island style")
        .navigationBarTitleDisplayMode(.inline)
    }
}
