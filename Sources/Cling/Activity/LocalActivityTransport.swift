/**
 ActivityKit transport — `Activity.request` and friends, in-process. The only
 file in the app that touches ActivityKit directly. Runs exactly one activity
 (the roster) and reconciles it against the current pin set.
 */
import Foundation
import ActivityKit

@MainActor
struct LocalActivityTransport: ActivityTransport {
    func syncRoster(_ snapshots: [PinSnapshot], staleDate: Date?, restart: Bool) async -> String? {
        // Nothing to show → tear the activity down.
        guard !snapshots.isEmpty else {
            await endRoster(dismissal: .immediate)
            return nil
        }

        // iOS caps a Live Activity content-state near 4 KB and SILENTLY drops any
        // update/request over it — the activity then freezes on stale/empty
        // content while the app still shows the full roster (an empty lock-screen
        // card). Trim the roster to fit: snapshots arrive hero-first (most
        // relevant first), so dropping from the tail keeps the pins that matter.
        let fitted = ActivityPushContract.fitToBudget(snapshots)
        #if DEBUG
        if fitted.count != snapshots.count {
            print("[Cling roster] trimmed \(snapshots.count)→\(fitted.count) pins to fit "
                  + "\(ActivityPushContract.contentStateBudget) B content-state budget")
        }
        #endif
        let state = ClingActivityAttributes.ContentState(pins: fitted, staleDate: staleDate)
        let content = ActivityContent(state: state, staleDate: staleDate, relevanceScore: 100)

        let existing = Activity<ClingActivityAttributes>.activities.first

        // Update in place — the cheap, flicker-free path.
        if let existing, !restart {
            await existing.update(content)
            return existing.id
        }

        // Restart (reset the ceiling) or first start: drop any current, request fresh.
        if let existing {
            await existing.end(existing.content, dismissalPolicy: .immediate)
        }
        do {
            // `.token` mints the activity's APNs update token (via
            // `pushTokenUpdates`), which the push server pushes refreshed roster
            // content state to while Cling is closed. Foreground updates still
            // go through `activity.update` above.
            let activity = try Activity.request(
                attributes: ClingActivityAttributes(),
                content: content,
                pushType: .token)
            return activity.id
        } catch {
            // Out of slots/budget, or activities disabled mid-flight — the
            // caller leaves the pins pending and the UI says so.
            return nil
        }
    }

    func endRoster(dismissal: PinDismissal) async {
        for activity in Activity<ClingActivityAttributes>.activities {
            await activity.end(
                activity.content,
                dismissalPolicy: dismissal == .immediate ? .immediate : .default)
        }
    }

    func rosterActivityID() -> String? {
        Activity<ClingActivityAttributes>.activities.first?.id
    }
}
