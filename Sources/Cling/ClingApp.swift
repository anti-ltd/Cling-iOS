import SwiftUI
import iUXiOS

@main
struct ClingApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // The glass language is built for dark — frosted surfaces,
                // dark ambient backdrop, white-based text. Following the
                // system into light mode collapses contrast (dark text on the
                // dark backdrop, faint labels on bright glass), so lock it.
                .preferredColorScheme(.dark)
        }
    }
}
