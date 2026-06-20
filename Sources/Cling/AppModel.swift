/**
 `AppModel`: app-wide observable state. Owns the pin list and settings,
 persisting every change to the App Group so the widget and share extensions
 see the same world. ClingKit types are available unqualified — the shared
 sources compile directly into this target.

 This is the single write path for pins; the Live Activity coordinator (next
 phase) observes these mutations to start/update/end activities.
 */
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class AppModel {
    /// The live settings. Mutating any field persists the whole value to the
    /// shared store so extensions read the same defaults.
    var settings: ClingSettings {
        didSet {
            store.saveSettings(settings)
            // The global house style changed — re-dress every pin (and push
            // the new look into anything live) so the change is instant.
            if settings.globalStyle != oldValue.globalStyle { restyleAllPins() }
        }
    }

    /// All pins, every status. Views filter what they need.
    private(set) var pins: [Pin] = []

    /// Whether the system allows Live Activities at all — surfaced honestly
    /// in the UI when off.
    var activitiesEnabled: Bool { coordinator.activitiesEnabled }

    private let store = ClingStore.shared
    private let coordinator = PinActivityCoordinator()
    private let renewals = RenewalScheduler()
    /// UNUserNotificationCenter holds its delegate weakly — owned here.
    private let notificationRouter = NotificationRouter()
    /// Collects APNs tokens so a server can push pins in (Tier 2 background
    /// pinning). Held for the app's lifetime.
    private let pushRegistrar = PushToStartRegistrar()
    /// Held for the app's lifetime; fires when another process (the share
    /// extension) writes pins.
    private var pinsToken: AnyObject?

    init() {
        settings = store.loadSettings()
        pins = coordinator.reconcile(store.loadPins())
        persist()
        pinsToken = store.observePins { [weak self] in
            Task { @MainActor in self?.reloadPins() }
        }
        coordinator.watchActivityStates { [weak self] pinID, status in
            self?.applyActivityState(pinID: pinID, status: status)
        }
        renewals.registerCategory()
        notificationRouter.onRenew = { [weak self] pinID in
            Task { await self?.activate(pinID: pinID) }
        }
        UNUserNotificationCenter.current().delegate = notificationRouter
        // Start collecting push tokens. The upload sink is left unset until the
        // server exists; tokens persist locally meanwhile (see PushTokenStore).
        pushRegistrar.start()
        reapOrphanedPhotos()
        sweepPendingPins()
        renewExpiringPins()
    }

    /// Re-read the shared store — after a Darwin change notification or a
    /// scene foreground (the share extension may have added a pending pin).
    func reloadPins() {
        pins = coordinator.reconcile(store.loadPins())
        persist()
    }

    /// Activate everything still waiting for the app (share-extension pins,
    /// failed earlier starts). Called on init and every foreground.
    func sweepPendingPins() {
        for pin in pins where pin.status == .pending {
            Task { await activate(pinID: pin.id) }
        }
    }

    /// Renew anything close to its stale date while we're conveniently in the
    /// foreground — most renewals happen here, invisibly, and the notification
    /// only fires for pins the user never came back for.
    func renewExpiringPins() {
        for pin in coordinator.pinsDueForRenewal(pins) {
            Task { await activate(pinID: pin.id) }
        }
    }

    /// Start (or renew) the pin's Live Activity and persist the outcome.
    func activate(pinID: UUID) async {
        guard let pin = pin(id: pinID) else { return }
        let updated = await coordinator.activate(pin)
        applyWithoutSideEffects(updated)
        renewals.cancelRenewal(for: updated.id)
        if updated.status == .live, settings.renewalRemindersEnabled {
            renewals.scheduleRenewal(for: updated)
        }
    }

    /// The coordinator observed the system changing an activity's state.
    private func applyActivityState(pinID: UUID, status: PinStatus) {
        guard var pin = pin(id: pinID) else { return }
        guard pin.status != status else { return }
        pin.status = status
        if status != .live { pin.activityID = nil }
        applyWithoutSideEffects(pin)
    }

    /// Store a mutated pin without triggering activity side effects (the
    /// mutation came FROM the activity layer).
    private func applyWithoutSideEffects(_ pin: Pin) {
        guard let i = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        pins[i] = pin
        persist()
    }

    // MARK: - Pin CRUD

    /// Pins visible in the main list (everything not fully ended).
    var activePins: [Pin] {
        pins.filter { $0.status != .ended }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - The app dresses itself in its pins

    /// The pin whose look leads the app's chrome: the newest live pin, else
    /// the newest active one. Nil when the board is clear.
    var heroPin: Pin? {
        activePins.first { $0.status == .live } ?? activePins.first
    }

    /// The accent driving tint/cards — the hero pin's, falling back to the
    /// app's own colour when nothing is pinned.
    var chromeAccent: Color {
        heroPin?.appearance.accent.color ?? settings.appAccent.color
    }

    /// The backdrop mesh: every active pin's accent (hero first, deduped).
    /// Empty board gets a designed two-tone default so a fresh install still
    /// has an identity.
    var backdropTints: [Color] {
        var seen: [RGBA] = []
        for pin in activePins where !seen.contains(pin.appearance.accent) {
            seen.append(pin.appearance.accent)
        }
        if let hero = heroPin, let i = seen.firstIndex(of: hero.appearance.accent), i != 0 {
            seen.swapAt(0, i)
        }
        guard !seen.isEmpty else {
            return [settings.appAccent.color, RGBA(hex: 0x9A5BD9).color]
        }
        return seen.map(\.color)
    }

    @discardableResult
    func createPin(payload: PinPayload, appearance: PinAppearance? = nil) -> Pin {
        let base = appearance ?? settings.defaultAppearance(for: payload.typeID)
        let pin = Pin(
            payload: payload,
            endDate: userEndDate(of: payload),
            appearance: settings.styled(base),
            status: .pending
        )
        pins.append(pin)
        persist()
        Task { await activate(pinID: pin.id) }
        return pin
    }

    /// Apply a content/appearance edit and push it into the live activity.
    /// Re-bakes the global house style so a per-pin accent/glyph edit can't
    /// drift the shared surface/type/density/border.
    func update(_ pin: Pin) {
        guard let i = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        var styled = pin
        styled.appearance = settings.styled(pin.appearance)
        pins[i] = styled
        persist()
        if styled.status == .live {
            Task { await coordinator.refresh(styled) }
        }
    }

    /// Re-apply the global house style to every pin and re-push the live ones.
    /// Called when `settings.globalStyle` changes — one knob re-dresses the
    /// whole board (and the Dynamic Island) at once.
    private func restyleAllPins() {
        for i in pins.indices {
            pins[i].appearance = settings.styled(pins[i].appearance)
        }
        persist()
        for pin in pins where pin.status == .live {
            Task { await coordinator.refresh(pin) }
        }
    }

    func delete(_ pin: Pin) {
        if let filename = photoFilename(of: pin.payload) {
            PhotoStore.shared.delete(filename)
        }
        pins.removeAll { $0.id == pin.id }
        persist()
        renewals.cancelRenewal(for: pin.id)
        Task { _ = await coordinator.end(pin, dismissal: .immediate) }
    }

    func pin(id: UUID) -> Pin? {
        pins.first { $0.id == id }
    }

    /// Write to the shared store without notifying — these are self-originated
    /// changes and our own state is already current. The home-screen widget,
    /// being a separate process, can't observe our in-memory state, so nudge
    /// WidgetCenter to re-read the store it shares with us.
    private func persist() {
        store.savePins(pins, notify: false)
        WidgetCenter.shared.reloadTimelines(ofKind: ClingKit.homeWidgetKind)
    }

    /// The user-meaningful end a payload implies (a timer's zero moment).
    private func userEndDate(of payload: PinPayload) -> Date? {
        if case .timer(let timer) = payload { return timer.endDate }
        return nil
    }

    /// Photos no pin references anymore — picked-then-cancelled attachments,
    /// pins deleted by a process that couldn't clean up.
    private func reapOrphanedPhotos() {
        let referenced = Set(pins.compactMap { photoFilename(of: $0.payload) })
        PhotoStore.shared.reapOrphans(referenced: referenced)
    }

    private func photoFilename(of payload: PinPayload) -> String? {
        switch payload {
        case .parking(let parking): parking.photoFilename
        case .note(let note):       note.photoFilename
        case .timer, .decor:        nil
        }
    }
}
