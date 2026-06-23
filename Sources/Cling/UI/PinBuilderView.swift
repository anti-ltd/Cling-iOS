/**
 The pin builder: a two-step flow. First you pick *what* to pin — a gallery of
 type cards (grouped Everyday / Live) plus your saved presets for a one-tap
 start. Then you compose: a live lock-screen preview, the type's content fields,
 and a single tap to Pin it. The look (colour, icon, gradient) is sensible by
 default and tucked behind a "Customize look" sheet, so content leads and the
 common path is fast.
 */
import SwiftUI
import PhotosUI
import iUXiOS

struct PinBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = PinDraft()
    @State private var appearance: PinAppearance
    @State private var location = LocationCapturer()
    @State private var photoItem: PhotosPickerItem?
    /// Empty = the type gallery; otherwise the pushed route.
    @State private var path: [BuilderRoute] = []
    @State private var showAppearance = false
    @State private var namingPreset = false
    @State private var presetName = ""

    /// Where a gallery tap goes: composing a hand-made type, or the live-sports
    /// fixture browser (the only way to make a working live pin — it carries a
    /// feed `sourceID` the push server can update).
    private enum BuilderRoute: Hashable {
        case compose(PinTypeID)
        case live
    }

    /// The everyday, hand-made types. Live pins (game/UFC/match) are *not* here:
    /// they're created by picking a real fixture in the live-sports browser, so
    /// they always have a feed id and actually update.
    private let everydayTypes: [PinTypeID] = [.note, .timer, .parking, .decor]

    init() {
        // Settings aren't reachable before the environment lands; seed with
        // the shipped default and adopt the user's when a type is chosen.
        _appearance = State(initialValue: ClingSettings.default.defaultAppearance(for: .note))
    }

    private var payload: PinPayload? { draft.payload() }
    private var problem: String? {
        guard let payload else { return nil }
        return PinRegistry.module(for: draft.typeID).validate(payload)
    }

    var body: some View {
        NavigationStack(path: $path) {
            typeGallery
                .navigationDestination(for: BuilderRoute.self) { route in
                    switch route {
                    case .compose:
                        composeScreen
                    case .live:
                        LiveSportsList(onPinned: { dismiss() })
                            .navigationTitle("Live sports")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
        }
        .background {
            // The signature living-glass backdrop, tinted by the current look —
            // so the sheet reads like the rest of the app, not a flat panel.
            AmbientBackdrop(tint: appearance.accent.color)
                .ignoresSafeArea()
                .animation(UX.Motion.morph, value: appearance.accent)
        }
        .tint(appearance.accent.color)
        .environment(\.cardTint, appearance.accent.color)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
        .onChange(of: path) { _, path in
            // Leaving the parking composer (back to the gallery, live browser, etc.)
            // must stop any in-flight fix so the location arrow clears.
            if case .compose(.parking) = path.last { return }
            location.cancel()
        }
        .onDisappear {
            location.cancel()
            // A picked-but-never-pinned photo would orphan; the launch reap
            // catches it, but clean up eagerly when we know.
            if let filename = draft.photoFilename, draft.payload() == nil {
                PhotoStore.shared.delete(filename)
            }
        }
        .sheet(isPresented: $showAppearance) { appearanceSheet }
        .alert("Name this preset", isPresented: $namingPreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) { presetName = "" }
        } message: {
            Text("It'll appear in the gallery, ready to pin.")
        }
    }

    // MARK: - Step 1: type gallery

    private var typeGallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UX.cardSpacing) {
                if !model.settings.customPresets.isEmpty {
                    presetShelf
                }
                typeShelf("Everyday", types: everydayTypes)
                liveSportsShelf
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("New pin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel") { dismiss() }
                    .tint(.red)
            }
        }
    }

    /// One-tap starts — the user's saved custom looks. The built-in per-type
    /// presets are redundant with the gallery below, so only customs show here.
    private var presetShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Quick start")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.settings.customPresets) { preset in
                        Chip(preset.name, systemImage: preset.appearance.symbolName) {
                            apply(preset)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                model.settings.customPresets.removeAll { $0.id == preset.id }
                            } label: {
                                Label("Delete preset", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder private func typeShelf(_ title: String, types: [PinTypeID]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title)
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(types, id: \.self) { typeID in
                    typeCard(typeID)
                }
            }
        }
    }

    private func typeCard(_ typeID: PinTypeID) -> some View {
        let module = PinRegistry.module(for: typeID)
        let tint = model.settings.defaultAppearance(for: typeID).accent.color
        return Button {
            choose(typeID)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                GlyphTile(systemName: module.systemImage, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(Self.hint(for: typeID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous))
            .glassTile(tint: tint)
        }
        .buttonStyle(.glassBloom)
    }

    /// Live scores come from real fixtures — one entry opens the sports browser.
    private var liveSportsShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Live")
            Button {
                path = [.live]
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    GlyphTile(systemName: "sportscourt.fill", tint: PinAppearance.mint.color, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live sports")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("World Cup, NBA, UFC…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .padding(14)
                .contentShape(RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous))
                .glassTile(tint: PinAppearance.mint.color)
            }
            .buttonStyle(.glassBloom)
        }
    }

    /// A one-line gallery hint per type — what you get, in a few words.
    private static func hint(for typeID: PinTypeID) -> String {
        switch typeID {
        case .note:    "Text or a photo"
        case .timer:   "Countdown to zero"
        case .parking: "Where you parked"
        case .decor:   "Dress the island"
        case .game:    "Live score"
        case .fight:   "Live fight card"
        case .ticker:  "Track a price"
        case .match:   "World Cup match"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize()
            Rectangle()
                .fill(appearance.accent.color.opacity(0.4))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Step 2: compose

    private var composeScreen: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                // What you're building, as the lock screen will draw it.
                PinPreviewCard(
                    typeID: draft.typeID,
                    payload: payload ?? SamplePayloads.payload(for: draft.typeID),
                    appearance: appearance)

                CardSection("Content", accentRule: true) {
                    PinRegistry.module(for: draft.typeID).quickAddForm(draft: $draft)
                }

                if draft.typeID == .parking {
                    parkingCapture
                }

                customizeLookRow

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
        .animation(UX.Motion.morph, value: draft.typeID)
        .onSubmit(commit)
        .navigationTitle(PinRegistry.module(for: draft.typeID).displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The single appearance entry on the compose screen — defaults are good, so
    /// the look stays one tap away rather than crowding the content.
    private var customizeLookRow: some View {
        CardSection {
            Button {
                showAppearance = true
            } label: {
                HStack(spacing: 12) {
                    GlyphTile(systemName: "paintbrush.fill", tint: .pink, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Customize look")
                            .foregroundStyle(.primary)
                        Text("Colour, icon, gradient")
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

    // MARK: - Appearance sheet

    private var appearanceSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    CardSection("Preview", accentRule: true) {
                        PinPreviewCard(
                            typeID: draft.typeID,
                            payload: payload ?? SamplePayloads.payload(for: draft.typeID),
                            appearance: appearance)
                            .padding(.vertical, UX.rowVPadding)
                    }
                    AppearanceControls(typeID: draft.typeID, appearance: $appearance)
                }
                .padding(UX.screenPadding)
            }
            .background {
                AmbientBackdrop(tints: [appearance.accent.color,
                                        appearance.accentEnd?.color].compactMap(\.self))
                    .ignoresSafeArea()
                    .animation(UX.Motion.morph, value: appearance)
            }
            .navigationTitle("Customize look")
            .navigationBarTitleDisplayMode(.inline)
            .tint(appearance.accent.color)
            .environment(\.cardTint, appearance.accent.color)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presetName = ""
                        namingPreset = true
                    } label: {
                        Label("Save preset", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAppearance = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Selection

    /// Pick a type from the gallery: reset to a clean draft of that type, adopt
    /// its default look, start a parking fix if needed, and push compose.
    private func choose(_ typeID: PinTypeID) {
        draft = PinDraft(typeID: typeID)
        appearance = model.settings.defaultAppearance(for: typeID)
        if typeID == .parking { location.capture() } else { location.cancel() }
        path = [.compose(typeID)]
    }

    /// Apply a preset and jump straight to compose with its type + look seeded.
    private func apply(_ preset: PinPreset) {
        draft = PinDraft(typeID: preset.typeID)
        appearance = preset.appearance
        if let duration = preset.duration {
            draft.duration = duration
        }
        if preset.typeID == .parking { location.capture() } else { location.cancel() }
        path = [.compose(preset.typeID)]
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = PinPreset(
            name: name.isEmpty ? PinRegistry.module(for: draft.typeID).displayName : name,
            typeID: draft.typeID,
            appearance: appearance,
            duration: draft.typeID == .timer ? draft.duration : nil)
        model.settings.customPresets.append(preset)
        presetName = ""
        #if canImport(UIKit)
        Haptics.success()
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
        Haptics.commit()
        #endif
        dismiss()
    }
}
