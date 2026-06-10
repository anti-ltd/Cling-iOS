/**
 Widget extension entry point — hosts the Live Activity.
 */
import SwiftUI
import WidgetKit

@main
struct ClingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ClingLiveActivity()
    }
}
