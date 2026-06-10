/**
 Appearance editing — accent, icon, density, surface style — with the pin's
 real renderers as the live preview: the lock-screen card and a mock Dynamic
 Island pill, drawn by the same code the widget runs. What you tune is
 literally what you'll see.

 Split into reusable pieces:
 - `PinPreviewCard` — the live preview (also the builder's header).
 - `AppearanceControls` — the colour/icon/layout sections (also inlined in
   the builder).
 - `AppearanceEditor` — preview + controls, on a `Binding<PinAppearance>` so
   the same screen serves a live pin (PinDetailView) and the per-type
   defaults (SettingsView).
 */
import SwiftUI
import iUXiOS

struct AppearanceEditor: View {
    let typeID: PinTypeID
    /// The payload driving the preview — the pin's own, or a sample.
    let previewPayload: PinPayload
    @Binding var appearance: PinAppearance

    var body: some View {
        VStack(spacing: UX.cardSpacing) {
            CardSection("Preview") {
                PinPreviewCard(typeID: typeID, payload: previewPayload, appearance: appearance)
                    .padding(.vertical, UX.rowVPadding)
            }
            AppearanceControls(typeID: typeID, appearance: $appearance)
        }
    }
}

// MARK: - Live preview

/// The pin as the widget will draw it: lock-screen card on its style's
/// surface, plus the compact Dynamic Island as iOS composes it.
struct PinPreviewCard: View {
    let typeID: PinTypeID
    let payload: PinPayload
    let appearance: PinAppearance

    private var context: PinRenderContext {
        PinRenderContext(pinID: UUID(), payload: payload, appearance: appearance)
    }

    var body: some View {
        let module = PinRegistry.module(for: typeID)
        VStack(spacing: 12) {
            module.lockScreen(context)
                .padding(.horizontal, 14)
                .padding(.vertical, appearance.density == .compact ? 10 : 14)
                .background(previewSurface)

            HStack(spacing: 8) {
                module.diCompactLeading(context)
                Capsule()
                    .fill(.black)
                    .frame(width: 36, height: 24)
                module.diCompactTrailing(context)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black))
            .environment(\.colorScheme, .dark)
        }
        .frame(maxWidth: .infinity)
        .fontDesign(appearance.fontDesign.design)
        .animation(UX.Motion.morph, value: appearance)
    }

    /// Approximates the activity background tint the lock screen applies.
    @ViewBuilder private var previewSurface: some View {
        let rr = RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous)
        switch appearance.style {
        case .glass:
            rr.fill(.ultraThinMaterial)
                .overlay(rr.fill(appearance.accent.color.opacity(0.18)))
        case .solid:
            rr.fill(.ultraThinMaterial)
                .overlay(rr.fill(appearance.accent.color.opacity(0.55)))
        case .outline:
            rr.fill(.ultraThinMaterial)
                .overlay(rr.strokeBorder(appearance.accent.color.opacity(0.5), lineWidth: 1))
        }
    }
}

// MARK: - Controls

/// The colour / icon / layout sections, preview-less so the pin builder can
/// inline them under its own header.
struct AppearanceControls: View {
    let typeID: PinTypeID
    @Binding var appearance: PinAppearance

    var body: some View {
        VStack(spacing: UX.cardSpacing) {
            colorSection
            iconSection
            layoutSection
        }
    }

    private var colorSection: some View {
        CardSection("Color") {
            VStack(alignment: .leading, spacing: 12) {
                swatchRow(
                    selected: appearance.accent,
                    custom: customAccent
                ) { appearance.accent = $0 }

                // Two-stop gradient accent: pick the second colour and the
                // glyph/surfaces blend toward it.
                Toggle(isOn: gradientEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Gradient")
                            .font(.callout)
                        Text("Blend the accent into a second colour")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if appearance.accentEnd != nil {
                    swatchRow(
                        selected: appearance.accentEnd,
                        custom: customAccentEnd
                    ) { appearance.accentEnd = $0 }
                }
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    private func swatchRow(
        selected: RGBA?,
        custom: Binding<Color>,
        choose: @escaping (RGBA) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ForEach(PinAppearance.accentPresets, id: \.self) { swatch in
                Button {
                    withAnimation(UX.Motion.morph) { choose(swatch) }
                } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 34, height: 34)
                        .overlay {
                            if selected == swatch {
                                Circle().strokeBorder(.white, lineWidth: 2)
                                    .padding(2)
                            }
                        }
                }
                .buttonStyle(.glassBloom)
            }
            Spacer(minLength: 0)
            ColorPicker("", selection: custom, supportsOpacity: false)
                .labelsHidden()
        }
    }

    private var gradientEnabled: Binding<Bool> {
        Binding(
            get: { appearance.accentEnd != nil },
            set: { on in
                withAnimation(UX.Motion.morph) {
                    // Seed the second stop with a rotated preset so flipping
                    // the toggle shows a gradient immediately.
                    appearance.accentEnd = on ? defaultEndStop : nil
                }
            })
    }

    private var defaultEndStop: RGBA {
        let presets = PinAppearance.accentPresets
        guard let i = presets.firstIndex(of: appearance.accent) else { return presets[0] }
        return presets[(i + 1) % presets.count]
    }

    private var customAccent: Binding<Color> {
        Binding(
            get: { appearance.accent.color },
            set: { appearance.accent = RGBA($0) })
    }

    private var customAccentEnd: Binding<Color> {
        Binding(
            get: { (appearance.accentEnd ?? appearance.accent).color },
            set: { appearance.accentEnd = RGBA($0) })
    }

    private var iconSection: some View {
        CardSection("Icon") {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(PinRegistry.module(for: typeID).symbolChoices, id: \.self) { symbol in
                    symbolChip(symbol)
                }
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    /// An icon-only selectable pill — `Chip` wants a title, so this draws the
    /// same capsule language for a bare glyph.
    private func symbolChip(_ symbol: String) -> some View {
        let selected = appearance.symbolName == symbol
        return Button {
            withAnimation(UX.Motion.morph) { appearance.symbolName = symbol }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 32)
                .background {
                    if selected {
                        Capsule().fill(appearance.accent.color)
                            .overlay(Capsule().strokeBorder(
                                .white.opacity(UX.Glass.rimTopOpacity),
                                lineWidth: UX.Glass.rimWidth))
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(.white.opacity(UX.Glass.baseFillOpacity)))
                    }
                }
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.glassBloom)
    }

    private var layoutSection: some View {
        CardSection("Layout") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Density")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                OptionChips(
                    options: [("Compact", LayoutDensity.compact), ("Regular", .regular)],
                    selection: $appearance.density)
                Text("Surface")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                OptionChips(
                    options: [("Glass", PinStyle.glass), ("Solid", .solid), ("Outline", .outline)],
                    selection: $appearance.style)
                Text("Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                OptionChips(
                    options: [
                        ("Standard", PinFontDesign.standard), ("Rounded", .rounded),
                        ("Serif", .serif), ("Mono", .mono),
                    ],
                    selection: $appearance.fontDesign)
                Toggle(isOn: $appearance.showsExpiry) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show expiry time")
                            .font(.callout)
                        Text("The \"pinned until\" line on the lock screen. You'll still get the renewal nudge either way.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }
}

/// The editor bound to a live pin — edits push straight into the running
/// activity via `AppModel.update`.
struct PinAppearanceEditorView: View {
    @Environment(AppModel.self) private var model
    let pin: Pin
    @State private var appearance: PinAppearance

    init(pin: Pin) {
        self.pin = pin
        _appearance = State(initialValue: pin.appearance)
    }

    var body: some View {
        ScrollView {
            AppearanceEditor(
                typeID: pin.typeID,
                previewPayload: pin.payload,
                appearance: $appearance)
                .padding(UX.screenPadding)
        }
        .background {
            AmbientBackdrop(tints: [appearance.accent.color,
                                    appearance.accentEnd?.color].compactMap(\.self))
                .ignoresSafeArea()
                .animation(UX.Motion.morph, value: appearance)
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: appearance) { _, new in
            var updated = pin
            updated.appearance = new
            model.update(updated)
        }
    }
}

/// Sample payloads so default-appearance editing previews something real.
enum SamplePayloads {
    static func payload(for typeID: PinTypeID) -> PinPayload {
        switch typeID {
        case .note:
            .note(NotePayload(text: "Pick up the dry cleaning"))
        case .timer:
            .timer(TimerPayload(label: "Pasta", startDate: .now, endDate: .now.addingTimeInterval(12 * 60)))
        case .parking:
            .parking(ParkingPayload(latitude: 0, longitude: 0, note: "Level 3, row F"))
        case .clipboard:
            .clipboard(ClipboardPayload(text: "482 916"))
        }
    }
}
