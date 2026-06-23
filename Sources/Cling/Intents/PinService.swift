/**
 `PinService`: create-and-activate as one headless operation. App Intents run
 in the app's process but not necessarily with the UI up, so this facade goes
 straight to the store + a coordinator; a running `AppModel` finds out via the
 store's Darwin notification and reloads.
 */
import Foundation

@MainActor
enum PinService {
    /// Create a pin from a payload, activate its Live Activity, persist, and
    /// schedule the renewal nudge. The one code path shared by every intent.
    @discardableResult
    static func createAndActivate(_ payload: PinPayload) async -> Pin {
        let store = ClingStore.shared
        let settings = store.loadSettings()

        let newPin = Pin(
            payload: payload,
            endDate: { if case .timer(let t) = payload { t.endDate } else { nil } }(),
            appearance: settings.styled(settings.defaultAppearance(for: payload.typeID)),
            status: .pending)

        // Add to the full set and rebuild the single roster activity — the new
        // pin joins the others rather than starting an activity of its own.
        let coordinator = PinActivityCoordinator()
        var all = store.loadPins()
        all.append(newPin)
        let synced = await coordinator.syncRoster(all)
        // notify: a running app instance reloads and shows the new pin.
        store.savePins(synced, notify: true)

        let result = synced.first { $0.id == newPin.id } ?? newPin
        if result.status == .live, settings.renewalRemindersEnabled {
            let renewals = RenewalScheduler()
            renewals.registerCategory()
            renewals.scheduleRenewal(for: result)
        }
        return result
    }
}
