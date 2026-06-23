/**
 Settings hub: a short list of category rows, each pushing a focused page —
 General (reminders, directions), Live sports (play-by-play), and Appearance
 (app colour and per-type pin defaults). Mirrors the iUX home-hub language:
 home-hub language: signature glyph tiles, accent-rule headers, glass cards.
 */
import SwiftUI
import iUXiOS

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection {
                    NavRow("General",
                           subtitle: "Reminders and directions",
                           systemImage: "slider.horizontal.3", glyphTint: .gray) {
                        GeneralSettings()
                    }
                    Divider()
                    NavRow("Live sports",
                           subtitle: "Play-by-play commentary",
                           systemImage: "sportscourt.fill", glyphTint: .green) {
                        LiveSportsSettings()
                    }
                    Divider()
                    NavRow("Appearance",
                           subtitle: "Colour and pin defaults",
                           systemImage: "paintbrush.fill", glyphTint: .pink) {
                        AppearanceSettings()
                    }
                }

                CardSection {
                    NavRow("Changelog",
                           subtitle: "What's new in Cling",
                           systemImage: "list.bullet.rectangle", glyphTint: .indigo) {
                        ChangelogView()
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
}

// MARK: - General

/// Everyday knobs: the renewal nudge and which maps app directions open in.
private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Pins", accentRule: true) {
                    ToggleRow(
                        "Renewal reminders",
                        subtitle: "iOS unpins everything after 8 hours. Get a nudge shortly before, so a tap keeps it alive.",
                        isOn: $model.settings.renewalRemindersEnabled)
                }

                CardSection("Directions", accentRule: true) {
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
            }
            .padding(UX.screenPadding)
        }
        .background {
            AmbientBackdrop(tint: model.settings.appAccent.color)
                .ignoresSafeArea()
        }
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Live sports

/// Live-score behaviour: whether the card carries the latest match event.
private struct LiveSportsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Live sports", accentRule: true) {
                    ToggleRow(
                        "Play-by-play",
                        subtitle: "Show the latest match event under the score — \u{201C}\u{2026} takes a throw-in\u{201D}. Off keeps the quieter score-only card.",
                        isOn: $model.settings.matchPlayByPlay)
                }

                if model.settings.matchPlayByPlay {
                    CardSection("Auto-expand", accentRule: true) {
                        VStack(alignment: .leading, spacing: UX.rowVPadding) {
                            Text("Pop the Dynamic Island open on a fresh line instead of updating it silently.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                ForEach(MatchCommentaryAlerts.allCases, id: \.self) { level in
                                    let selected = model.settings.matchCommentaryAlerts == level
                                    Button {
                                        withAnimation(UX.Motion.morph) {
                                            model.settings.matchCommentaryAlerts = level
                                        }
                                    } label: {
                                        Text(level.displayName)
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
                        }
                        .padding(.vertical, UX.rowVPadding)

                        if model.settings.matchCommentaryAlerts != .off {
                            ToggleRow(
                                "Sound & haptic",
                                subtitle: "Play the default ping when the island expands. Off shows a silent banner.",
                                isOn: $model.settings.matchCommentaryAlertSound)
                        }
                    }
                }
            }
            .padding(UX.screenPadding)
        }
        .background {
            AmbientBackdrop(tint: model.settings.appAccent.color)
                .ignoresSafeArea()
        }
        .navigationTitle("Live sports")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Appearance

/// Pin types shown in "New pins look like". Match is folded into Sports (`.game`).
private let appearanceTypeRows: [PinTypeID] = [
    .note, .timer, .parking, .decor, .game, .fight, .ticker,
]

/// Everything that shapes how pins look: the app accent and per-type defaults.
private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("App colour", accentRule: true) {
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

                CardSection("New pins look like", accentRule: true) {
                    ForEach(Array(appearanceTypeRows.enumerated()), id: \.element) { index, typeID in
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
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func defaultAppearanceRow(_ typeID: PinTypeID) -> some View {
        let appearance = model.settings.defaultAppearance(for: typeID)
        let label = typeID == .game ? "Sports" : PinRegistry.module(for: typeID).displayName
        NavRow(label, systemImage: appearance.symbolName,
               glyphTint: appearance.accent.color) {
            if typeID == .game {
                SportsDefaultAppearanceEditor()
            } else {
                DefaultAppearanceEditor(typeID: typeID)
            }
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

/// Football matches and US-league games share one default look.
private struct SportsDefaultAppearanceEditor: View {
    @Environment(AppModel.self) private var model
    @State private var previewSport: SportsPreview = .basketball

    private enum SportsPreview: String, CaseIterable {
        case football, basketball

        var label: String {
            switch self {
            case .football:   "Football"
            case .basketball: "US leagues"
            }
        }

        var typeID: PinTypeID {
            switch self {
            case .football:   .match
            case .basketball: .game
            }
        }

        var payload: PinPayload {
            SamplePayloads.payload(for: typeID)
        }
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                Picker("Preview", selection: $previewSport) {
                    ForEach(SportsPreview.allCases, id: \.self) { sport in
                        Text(sport.label).tag(sport)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, UX.screenPadding)

                AppearanceEditor(
                    typeID: previewSport.typeID,
                    previewPayload: previewSport.payload,
                    appearance: Binding(
                        get: { model.settings.defaultAppearance(for: .game) },
                        set: { new in
                            model.settings.defaultAppearances[.game] = new
                            model.settings.defaultAppearances[.match] = new
                        }))
            }
            .padding(.bottom, UX.screenPadding)
        }
        .background {
            AmbientBackdrop(tint: model.settings.appAccent.color)
                .ignoresSafeArea()
        }
        .navigationTitle("Sports")
        .navigationBarTitleDisplayMode(.inline)
    }
}
