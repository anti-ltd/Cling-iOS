/**
 `PinActivityCoordinator`: the only client of the activity transport. Maps pin
 mutations to start/update/end, computes honest stale dates inside iOS's 8h
 ceiling, reconciles the store against the system's reality on launch, and
 watches activity state so a pin the system aged out is marked stale — never
 silently pretended live.
 */
import Foundation
import ActivityKit

@MainActor
final class PinActivityCoordinator {
    /// iOS caps a Live Activity at 8h of active life; we re-arm a minute shy
    /// of the edge so the system never beats us to it.
    static let maxActivityWindow: TimeInterval = 8 * 3600 - 60

    private let transport: any ActivityTransport

    init(transport: any ActivityTransport = LocalActivityTransport()) {
        self.transport = transport
    }

    /// Can this device/user show Live Activities at all? Surfaced honestly in
    /// the UI when not.
    var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// The honest expiry for a pin started/renewed now: its own end if sooner,
    /// otherwise the system ceiling.
    func staleDate(for pin: Pin, now: Date = .now) -> Date {
        min(pin.endDate ?? .distantFuture, now.addingTimeInterval(Self.maxActivityWindow))
    }

    // MARK: - Lifecycle

    /// Start (or restart, for renewal) the pin's activity. Returns the pin
    /// with its new status — `.live` on success, unchanged `.pending` when
    /// activities are disabled or the request fails.
    func activate(_ pin: Pin) async -> Pin {
        guard activitiesEnabled else { return pin }
        var pin = pin
        // A renewal restarts the clock: end any existing activity first.
        if let existing = pin.activityID {
            await transport.end(activityID: existing, dismissal: .immediate)
            pin.activityID = nil
        }
        do {
            let staleDate = staleDate(for: pin)
            pin.activityID = try transport.start(pin, staleDate: staleDate)
            pin.status = .live
            pin.staleDate = staleDate
        } catch {
            // Out of slots or budget — the pin stays pending and the UI says so.
        }
        return pin
    }

    /// Push edited content/appearance into the running activity.
    func refresh(_ pin: Pin) async {
        await transport.update(pin, staleDate: staleDate(for: pin))
    }

    /// End the pin's activity. Returns the pin marked `.ended`.
    func end(_ pin: Pin, dismissal: PinDismissal = .immediate) async -> Pin {
        var pin = pin
        if let activityID = pin.activityID {
            await transport.end(activityID: activityID, dismissal: dismissal)
        }
        pin.activityID = nil
        pin.status = .ended
        pin.staleDate = nil
        return pin
    }

    /// Pins whose activity is inside `window` of going stale and would gain
    /// life from a restart — renewed silently whenever the app foregrounds,
    /// so most users never even see the renewal notification.
    func pinsDueForRenewal(_ pins: [Pin], within window: TimeInterval = 30 * 60, now: Date = .now) -> [Pin] {
        pins.filter { pin in
            guard pin.isRenewable else { return false }
            switch pin.status {
            case .live:
                guard let staleDate = pin.staleDate else { return false }
                return staleDate.timeIntervalSince(now) < window
            case .stale:
                // Already aged out, but its content is still wanted (no
                // passed end date) — bring it back.
                return pin.endDate.map { $0 > now } ?? true
            case .pending, .ended:
                return false
            }
        }
    }

    // MARK: - Reconciliation

    /// Align the store with the system after a launch: activities can vanish
    /// while the app isn't running (8h ceiling, reboot, user swipe-dismiss).
    /// A pin that claims `.live` but has no backing activity becomes `.stale`
    /// — visible in the app, honest about no longer being pinned.
    func reconcile(_ pins: [Pin]) -> [Pin] {
        let running = transport.currentActivityIDs()
        return pins.map { pin in
            var pin = pin
            if let activityID = running[pin.id] {
                pin.activityID = activityID
                if pin.status == .pending || pin.status == .stale { pin.status = .live }
            } else if pin.status == .live {
                pin.activityID = nil
                pin.status = .stale
            }
            return pin
        }
    }

    /// Long-lived watcher: when the system moves an activity to stale or
    /// dismisses it, reflect that on the pin. `onChange` receives the pinID
    /// and the new status.
    func watchActivityStates(onChange: @escaping @MainActor (UUID, PinStatus) -> Void) {
        Task { @MainActor in
            for await activity in Activity<ClingActivityAttributes>.activityUpdates {
                let pinID = activity.attributes.pinID
                Task { @MainActor in
                    for await state in activity.activityStateUpdates {
                        switch state {
                        case .stale:
                            onChange(pinID, .stale)
                        case .dismissed, .ended:
                            onChange(pinID, .ended)
                        case .active:
                            onChange(pinID, .live)
                        @unknown default:
                            break
                        }
                    }
                }
            }
        }
        // Also watch activities that already exist at call time — the
        // activityUpdates stream only yields *new* requests.
        for activity in Activity<ClingActivityAttributes>.activities {
            let pinID = activity.attributes.pinID
            Task { @MainActor in
                for await state in activity.activityStateUpdates {
                    switch state {
                    case .stale:                onChange(pinID, .stale)
                    case .dismissed, .ended:    onChange(pinID, .ended)
                    case .active:               onChange(pinID, .live)
                    @unknown default:           break
                    }
                }
            }
        }
    }
}
