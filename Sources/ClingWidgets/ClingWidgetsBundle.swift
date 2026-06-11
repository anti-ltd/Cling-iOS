/**
 Widget extension entry point — hosts the Live Activity (lock screen + Dynamic
 Island) and the home-screen widget.
 */
import SwiftUI
import WidgetKit

@main
struct ClingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ClingLiveActivity()
        ClingHomeWidget()
    }
}
