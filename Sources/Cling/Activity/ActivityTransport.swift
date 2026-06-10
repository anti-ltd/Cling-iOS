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
    /// Start an activity for the pin. Returns the activity id.
    func start(_ pin: Pin, staleDate: Date) throws -> String

    /// Push fresh content (payload/appearance edits, renewed stale date) into
    /// the pin's running activity. No-op if none is running.
    func update(_ pin: Pin, staleDate: Date) async

    /// End the pin's activity.
    func end(activityID: String, dismissal: PinDismissal) async

    /// The system's view of what's running: pinID → activityID. Used to
    /// reconcile the store against reality on launch (iOS may have ended
    /// activities while we weren't running).
    func currentActivityIDs() -> [UUID: String]
}
