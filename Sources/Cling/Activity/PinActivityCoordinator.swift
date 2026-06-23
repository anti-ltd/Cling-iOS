/**
 `PinActivityCoordinator`: the only client of the activity transport. Maps the
 whole pin set to a single roster activity — start/update/end — computes honest
 stale dates inside iOS's 8 h ceiling, reconciles the store against the system's
 reality on launch, and watches the activity so pins the system aged out are
 marked stale rather than silently pretended live.

 One activity, not one-per-pin: iOS shows only a single activity in the Dynamic
 Island anyway, so Cling carries every live pin in that one activity's content
 state and renders them as a list (see `ClingActivityAttributes`).
 */
import Foundation
import ActivityKit

@MainActor
final class PinActivityCoordinator {
    /// iOS caps a Live Activity at 8 h of active life; we re-arm a minute shy
    /// of the edge so the system never beats us to it.
    static let maxActivityWindow: TimeInterval = 8 * 3600 - 60

    private let transport: any ActivityTransport

    /// The current activity's ceiling — set when it (re)starts, reused across
    /// in-place content updates so the per-row "Pinned until" stays honest
    /// instead of creeping forward on every score tick.
    private var rosterCeiling: Date?

    init(transport: any ActivityTransport = LocalActivityTransport()) {
        self.transport = transport
    }

    /// Can this device/user show Live Activities at all? Surfaced honestly in
    /// the UI when not.
    var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// The honest expiry for a single pin: its own end if sooner, otherwise the
    /// given activity ceiling.
    func staleDate(for pin: Pin, ceiling: Date) -> Date {
        min(pin.endDate ?? .distantFuture, ceiling)
    }

    // MARK: - Roster sync

    /// Reconcile the one roster activity with the current pin set. Every pin
    /// that should show (anything not `.ended`) becomes `.live`, carries the
    /// roster activity id and a fresh stale date; the rest are returned
    /// untouched. `restart` forces a ceiling-resetting restart (renewal).
    func syncRoster(_ pins: [Pin], restart: Bool = false, now: Date = .now) async -> [Pin] {
        guard activitiesEnabled else { return pins }
        var pins = pins

        let showIdx = pins.indices.filter { pins[$0].status != .ended }
        guard !showIdx.isEmpty else {
            await transport.endRoster(dismissal: .immediate)
            rosterCeiling = nil
            return pins
        }

        // A restart (or a first start, when nothing is running) resets the
        // ceiling; an in-place update keeps the one the activity began with.
        let starting = restart || transport.rosterActivityID() == nil
        let ceiling = starting
            ? now.addingTimeInterval(Self.maxActivityWindow)
            : (rosterCeiling ?? now.addingTimeInterval(Self.maxActivityWindow))

        // Hero first: the island shows whatever leads the list, so order by
        // relevance (deadlines outrank ambient pins, sooner deadlines first).
        let ordered = showIdx.sorted { relevance(pins[$0]) > relevance(pins[$1]) }
        let snapshots = ordered.map { i in
            pins[i].snapshot(staleDate: staleDate(for: pins[i], ceiling: ceiling))
        }
        let rosterStale = snapshots.compactMap(\.staleDate).max()

        let activityID = await transport.syncRoster(snapshots, staleDate: rosterStale, restart: restart)
        // Lock in the ceiling on a (re)start, and also the first time we adopt a
        // pre-existing activity after launch (its true start is unknown — this
        // estimate stays stable across later in-place updates instead of creeping
        // forward on every score tick).
        if activityID != nil, starting || rosterCeiling == nil { rosterCeiling = ceiling }

        for i in showIdx {
            pins[i].staleDate = staleDate(for: pins[i], ceiling: ceiling)
            if let activityID {
                pins[i].activityID = activityID
                pins[i].status = .live
            }
        }
        return pins
    }

    /// End the whole roster (last pin removed, activities disabled).
    func endRoster() async {
        await transport.endRoster(dismissal: .immediate)
        rosterCeiling = nil
    }

    // MARK: - Renewal

    /// Pins whose activity is inside `window` of going stale and would gain life
    /// from a restart. With one shared activity, *any* such pin means the whole
    /// roster should be restarted to reset its ceiling.
    func pinsDueForRenewal(_ pins: [Pin], within window: TimeInterval = 30 * 60, now: Date = .now) -> [Pin] {
        pins.filter { pin in
            guard pin.isRenewable else { return false }
            switch pin.status {
            case .live:
                guard let staleDate = pin.staleDate else { return false }
                return staleDate.timeIntervalSince(now) < window
            case .stale:
                // Already aged out, but its content is still wanted — bring it back.
                return pin.endDate.map { $0 > now } ?? true
            case .pending, .ended:
                return false
            }
        }
    }

    /// True when the roster is due a ceiling-resetting restart.
    func rosterNeedsRenewal(_ pins: [Pin], within window: TimeInterval = 30 * 60, now: Date = .now) -> Bool {
        !pinsDueForRenewal(pins, within: window, now: now).isEmpty
    }

    // MARK: - Reconciliation

    /// Align the store with the system after a launch: the roster activity can
    /// vanish while the app isn't running (8 h ceiling, reboot, swipe-dismiss).
    /// A pin that claims `.live` but has no backing activity becomes `.stale` —
    /// visible in the app, honest about no longer being pinned. The next
    /// `syncRoster` re-arms it.
    func reconcile(_ pins: [Pin]) -> [Pin] {
        let running = transport.rosterActivityID()
        return pins.map { pin in
            var pin = pin
            guard pin.status != .ended else { return pin }
            if let running {
                pin.activityID = running
                if pin.status == .stale { pin.status = .live }
            } else if pin.status == .live {
                pin.activityID = nil
                pin.status = .stale
            }
            return pin
        }
    }

    /// Long-lived watcher: when the system moves the roster activity to stale or
    /// dismisses it, report the new status. `onChange` is called with the status
    /// every shown pin should take.
    func watchRoster(onChange: @escaping @MainActor (PinStatus) -> Void) {
        Task { @MainActor in
            for await activity in Activity<ClingActivityAttributes>.activityUpdates {
                Task { @MainActor in
                    for await state in activity.activityStateUpdates {
                        onChange(Self.status(for: state))
                    }
                }
            }
        }
        // Also watch an activity that already exists at call time — the
        // activityUpdates stream only yields *new* requests.
        for activity in Activity<ClingActivityAttributes>.activities {
            Task { @MainActor in
                for await state in activity.activityStateUpdates {
                    onChange(Self.status(for: state))
                }
            }
        }
    }

    /// Dismissed/ended map to `.stale`, not `.ended`: the user swiping the
    /// island away shouldn't *delete* every pin from the in-app list — it just
    /// means nothing's currently pinned. They stay re-armable.
    private static func status(for state: ActivityState) -> PinStatus {
        switch state {
        case .active:               .live
        case .stale:                .stale
        case .dismissed, .ended:    .stale
        @unknown default:           .stale
        }
    }

    /// With several pins live, iOS uses relevance to pick who leads. Timers
    /// (which have a deadline) outrank ambient pins; sooner deadlines outrank
    /// later ones.
    private func relevance(_ pin: Pin) -> Double {
        guard let endDate = pin.endDate else { return 50 }
        let remaining = max(60, endDate.timeIntervalSinceNow)
        return 100 + 10_000 / remaining
    }
}
