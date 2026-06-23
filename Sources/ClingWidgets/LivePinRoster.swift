/**
 The multi-pin roster view. The single Live Activity carries every live pin in
 its content state, so when several are pinned we render them as a stack of
 per-type rows — each the pin type's `liveRow`, carrying its own inline action
 (Walk / Copy / countdown). Used by both the lock-screen card and the expanded
 island.

 Rows read straight from the activity's `[PinSnapshot]`; no App Group round-trip
 at render time, so each row is as current as the last activity update.
 */
import SwiftUI

/// The roster rendered as a stack of per-type rows. Each row links to its pin's
/// detail screen; a row's own inline control (when it has one) still wins its
/// own hit area.
struct LivePinListView: View {
    let pins: [PinSnapshot]
    var maxRows: Int = 4

    var body: some View {
        VStack(spacing: 8) {
            ForEach(pins.prefix(maxRows)) { snapshot in
                let module = PinRegistry.module(for: snapshot.typeID)
                let row = module.liveRow(snapshot.renderContext)
                // A row that carries its own control (Parking's Walk link) must NOT
                // be wrapped in an outer Link — nesting two interactive elements is
                // invalid SwiftUI and renders the whole Live Activity blank. Its own
                // action handles taps; the rest of the row falls to the activity's
                // widgetURL (opens the app).
                if module.liveRowHasInlineAction {
                    row
                } else {
                    Link(destination: DeepLink.pin(snapshot.id).url) { row }
                }
            }
            if pins.count > maxRows {
                Text("+\(pins.count - maxRows) more pinned")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
