/**
 The seam between pin lifecycle logic and however activities actually reach
 the system. `LocalActivityTransport` (ActivityKit, in-process) is the MVP;
 a push-based transport (APNs start/update tokens, iOS 17.2+) slots in behind
 the same protocol later — entitlement and token plumbing only, no caller
 changes.
 */
import Foundation

/// How a pin's activity should leave the screen.
enum PinDismissal {
    /// Gone now (user removed the pin).
    case immediate
    /// Let the system age it off the lock screen on its own schedule.
    case system
}

@MainActor
protocol ActivityTransport {
    /// Reconcile the single roster activity with `snapshots`: start one if none
    /// is running, update it in place if one is, end it if `snapshots` is empty.
    /// `restart` forces an end-and-restart even when one is running — the only
    /// way to reset the system's 8 h ceiling (used by renewal). Returns the id
    /// of the now-running activity, or nil if none runs (empty / start failed).
    @discardableResult
    func syncRoster(_ snapshots: [PinSnapshot], staleDate: Date?, restart: Bool) async -> String?

    /// End the roster activity outright.
    func endRoster(dismissal: PinDismissal) async

    /// The running roster activity's id, or nil — used to reconcile the store
    /// against reality on launch (iOS may have ended it while we weren't running).
    func rosterActivityID() -> String?
}
