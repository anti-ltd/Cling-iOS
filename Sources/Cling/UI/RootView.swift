/**
 The app's one screen: your pins, newest first, with the quick-add composer a
 thumb-reach away. Ambient backdrop tinted by the app accent; everything on
 liquid glass.
 */
import SwiftUI
import iUXiOS

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showComposer = false
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                // The backdrop is a mesh of the pins' own accents — the app
                // dresses itself in what you've pinned.
                AmbientBackdrop(tints: model.backdropTints)
                    .ignoresSafeArea()
                    .animation(UX.Motion.morph, value: model.backdropTints)
                PinListView(onAdd: { showComposer = true })
            }
            .navigationTitle("Cling")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UUID.self) { id in
                if let pin = model.pin(id: id) {
                    PinDetailView(pin: pin)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.glassBloom)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.glassBloom)
                }
            }
        }
        .tint(model.chromeAccent)
        .environment(\.cardTint, model.chromeAccent)
        .sheet(isPresented: $showComposer) {
            PinBuilderView()
                .glassSheet()
        }
        .onChange(of: scenePhase) { _, phase in
            // The share extension may have written pins while we were away;
            // pending pins can only be activated by this process.
            if phase == .active {
                model.reloadPins()
                model.sweepPendingPins()
                model.renewExpiringPins()
            }
        }
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            switch link {
            case .pin(let id):
                if model.pin(id: id) != nil { path = [id] }
            case .activate(let id):
                guard model.pin(id: id) != nil else { return }
                path = [id]
                Task { await model.activate(pinID: id) }
            }
        }
    }
}
