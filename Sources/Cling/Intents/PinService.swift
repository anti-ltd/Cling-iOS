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

        var pin = Pin(
            payload: payload,
            endDate: { if case .timer(let t) = payload { t.endDate } else { nil } }(),
            appearance: settings.defaultAppearance(for: payload.typeID),
            status: .pending)

        let coordinator = PinActivityCoordinator()
        pin = await coordinator.activate(pin)
        // notify: a running app instance reloads and shows the new pin.
        store.upsert(pin)

        if pin.status == .live, settings.renewalRemindersEnabled {
            let renewals = RenewalScheduler()
            renewals.registerCategory()
            renewals.scheduleRenewal(for: pin)
        }
        return pin
    }
}
