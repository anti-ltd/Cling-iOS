/**
 The multi-pin roster. iOS shows only the most-recently-updated activity in the
 Dynamic Island, and ActivityKit gives a widget no hook into sibling activities
 — so when several pins are live we read them from the shared App Group store at
 render time and list them ourselves. Each row is the pin type's `liveRow`,
 carrying its own inline action (Walk / Copy / countdown).

 The listed siblings are a store snapshot, refreshed whenever *this* activity
 re-renders; a timer in another row won't tick between updates, but its row is
 still present and honest.
 */
import SwiftUI

@MainActor
enum LivePinRoster {
    /// Pins currently on the lock screen — live, plus aged-to-stale (still
    /// shown, no longer fresh) — nearest expiry first.
    static func onScreen() -> [Pin] {
        ClingStore.shared.loadPins()
            .filter { $0.status == .live || $0.status == .stale }
            .sorted { ($0.staleDate ?? .distantFuture) < ($1.staleDate ?? .distantFuture) }
    }

    static func context(_ pin: Pin) -> PinRenderContext {
        PinRenderContext(
            pinID: pin.id,
            payload: pin.payload,
            appearance: pin.appearance,
            staleDate: pin.staleDate)
    }
}

/// The roster rendered as a stack of per-type rows, used by both the lock
/// screen and the expanded island when more than one pin is live.
struct LivePinListView: View {
    let pins: [Pin]
    var maxRows: Int = 4

    var body: some View {
        VStack(spacing: 8) {
            ForEach(pins.prefix(maxRows)) { pin in
                PinRegistry.module(for: pin.typeID).liveRow(LivePinRoster.context(pin))
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
