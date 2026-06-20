/**
 The pin builder: ONE creation page. A live preview leads (the literal
 lock-screen render of what you're building), presets get you started in a
 tap — the built-in four plus your saved customs — and the content fields and
 full appearance controls sit in the same flow, so a pin is composed, not
 just typed. Any look you like can be saved back as a preset.
 */
import SwiftUI
import PhotosUI
import iUXiOS

struct PinBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = PinDraft()
    @State private var appearance: PinAppearance
    @State private var selectedPresetID: UUID?
    @State private var location = LocationCapturer()
    @State private var photoItem: PhotosPickerItem?
    @State private var namingPreset = false
    @State private var presetName = ""

    init() {
        // Settings aren't reachable before the environment lands; seed with
        // the shipped default and adopt the user's in onAppear.
        _appearance = State(initialValue: ClingSettings.default.defaultAppearance(for: .note))
    }

    private var payload: PinPayload? { draft.payload() }
    private var problem: String? {
        guard let payload else { return nil }
        return PinRegistry.module(for: draft.typeID).validate(payload)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                // What you're building, as the lock screen will draw it.
                PinPreviewCard(
                    typeID: draft.typeID,
                    payload: payload ?? SamplePayloads.payload(for: draft.typeID),
                    appearance: appearance,
                    globalStyle: model.settings.globalStyle)

                presetRow

                CardSection("Content") {
                    PinRegistry.module(for: draft.typeID).quickAddForm(draft: $draft)
                }

                if draft.typeID == .parking {
                    parkingCapture
                }

                AppearanceControls(typeID: draft.typeID, appearance: manualAppearance)

                savePresetRow

                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(UX.screenPadding)
            .padding(.bottom, 72) // room above the pinned Pin-it button
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { pinItButton }
        .tint(appearance.accent.color)
        .environment(\.cardTint, appearance.accent.color)
        .animation(UX.Motion.morph, value: draft.typeID)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onSubmit(commit)
        .onAppear {
            appearance = model.settings.defaultAppearance(for: draft.typeID)
            selectedPresetID = model.settings.builderPresets().first?.id
        }
        .onChange(of: draft.typeID) { _, typeID in
            if typeID == .parking { location.capture() } else { location.cancel() }
        }
        .onChange(of: location.state) { _, state in
            if case .captured(let latitude, let longitude) = state {
                draft.latitude = latitude
                draft.longitude = longitude
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await attachPhoto(item) }
        }
        .onDisappear {
            location.cancel()
            // A picked-but-never-pinned photo would orphan; the launch reap
            // catches it, but clean up eagerly when we know.
            if let filename = draft.photoFilename, draft.payload() == nil {
                PhotoStore.shared.delete(filename)
            }
        }
        .alert("Name this preset", isPresented: $namingPreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) { presetName = "" }
        } message: {
            Text("It'll appear in the builder, ready to pin.")
        }
    }

    // MARK: - Presets

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.settings.builderPresets()) { preset in
                    Chip(
                        preset.name,
                        systemImage: preset.appearance.symbolName,
                        isSelected: selectedPresetID == preset.id
                    ) {
                        apply(preset)
                    }
                    .contextMenu {
                        if model.settings.customPresets.contains(where: { $0.id == preset.id }) {
                            Button(role: .destructive) {
                                model.settings.customPresets.removeAll { $0.id == preset.id }
                            } label: {
                                Label("Delete preset", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func apply(_ preset: PinPreset) {
        withAnimation(UX.Motion.morph) {
            selectedPresetID = preset.id
            draft.typeID = preset.typeID
            appearance = preset.appearance
            if let duration = preset.duration {
                draft.duration = duration
            }
        }
    }

    /// Editing appearance by hand makes the pin custom — the preset chip
    /// lets go, but everything it seeded stays.
    private var manualAppearance: Binding<PinAppearance> {
        Binding(
            get: { appearance },
            set: { new in
                appearance = new
                selectedPresetID = nil
            })
    }

    private var savePresetRow: some View {
        Button {
            presetName = ""
            namingPreset = true
        } label: {
            Label("Save this look as a preset", systemImage: "square.and.arrow.down")
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.glassBloom)
        .glassTile()
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = PinPreset(
            name: name.isEmpty ? PinRegistry.module(for: draft.typeID).displayName : name,
            typeID: draft.typeID,
            appearance: appearance,
            duration: draft.typeID == .timer ? draft.duration : nil)
        model.settings.customPresets.append(preset)
        selectedPresetID = preset.id
        presetName = ""
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    // MARK: - Parking capture

    @ViewBuilder private var parkingCapture: some View {
        HStack(spacing: 10) {
            switch location.state {
            case .denied:
                Label("Location denied — enable it in Settings", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .failed:
                Button {
                    location.capture()
                } label: {
                    Label("Couldn't get a fix — retry", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.glassBloom)
            default:
                EmptyView()
            }
            Spacer(minLength: 0)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    draft.photoFilename == nil ? "Add photo" : "Photo attached",
                    systemImage: draft.photoFilename == nil ? "camera" : "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.glassBloom)
        }
        .padding(.horizontal, 4)
    }

    private func attachPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        if let old = draft.photoFilename {
            PhotoStore.shared.delete(old)
        }
        draft.photoFilename = PhotoStore.shared.save(image)
    }

    // MARK: - Commit

    private var pinItButton: some View {
        Button(action: commit) {
            Label("Pin it", systemImage: "pin.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    Capsule().fill(AnyShapeStyle(appearance.accentGradient))
                        .overlay(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [.white.opacity(UX.Glass.sheenTopOpacity), .clear],
                                    startPoint: .top, endPoint: .bottom)
                            )
                        )
                }
                .foregroundStyle(.white)
        }
        .buttonStyle(.glassBloom)
        .disabled(payload == nil || problem != nil)
        .opacity(payload == nil || problem != nil ? 0.5 : 1)
        .padding(.horizontal, UX.screenPadding)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func commit() {
        guard let payload, problem == nil else { return }
        model.createPin(payload: payload, appearance: appearance)
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        dismiss()
    }
}
