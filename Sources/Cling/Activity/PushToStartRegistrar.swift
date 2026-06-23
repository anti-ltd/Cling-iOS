/**
 `PushToStartRegistrar`: Cling's half of the background-pin path. Subscribes to
 ActivityKit's token streams and parks the tokens in `PushTokenStore` for a
 server to collect and push against.

 - `pushToStartTokenUpdates` (iOS 17.2+) yields the install-wide token a server
   uses to START a new activity while Cling is closed — the whole point of
   Tier 2. Cling must have launched at least once to mint it.
 - each running activity's `pushTokenUpdates` yields the token for UPDATING or
   ENDING that specific activity by push.

 Caller wires an `onTokensChanged` sink (upload to the Worker). Until that Worker
 exists the tokens still persist locally, so flipping it on later is a one-liner.
 Start this once and let it run for the app's lifetime.
 */
import Foundation
import ActivityKit

@MainActor
final class PushToStartRegistrar {
    private let tokens = PushTokenStore.shared
    private var started = false

    /// Fired after any token is recorded — hook the server upload here.
    var onTokensChanged: (@MainActor (PushTokens) -> Void)?

    /// Begin watching all token streams. Idempotent.
    func start() {
        guard !started else { return }
        started = true
        watchPushToStart()
        watchExistingActivities()
        watchNewActivities()
    }

    // MARK: - Push-to-start (install-wide)

    private func watchPushToStart() {
        Task { @MainActor in
            for await tokenData in Activity<ClingActivityAttributes>.pushToStartTokenUpdates {
                tokens.setPushToStart(Self.hex(tokenData))
                onTokensChanged?(tokens.load())
            }
        }
    }

    // MARK: - Per-activity update tokens

    /// Activities already running when we start (the stream below only yields
    /// NEW ones).
    private func watchExistingActivities() {
        for activity in Activity<ClingActivityAttributes>.activities {
            observeUpdateToken(of: activity)
        }
    }

    private func watchNewActivities() {
        Task { @MainActor in
            for await activity in Activity<ClingActivityAttributes>.activityUpdates {
                observeUpdateToken(of: activity)
            }
        }
    }

    private func observeUpdateToken(of activity: Activity<ClingActivityAttributes>) {
        // One roster activity → one update token; a server pushes the whole
        // refreshed content state to it.
        Task { @MainActor in
            for await tokenData in activity.pushTokenUpdates {
                tokens.setRosterUpdateToken(Self.hex(tokenData))
                onTokensChanged?(tokens.load())
            }
            // Stream finishing means the activity ended — drop its stale token.
            tokens.removeRosterUpdateToken()
            onTokensChanged?(tokens.load())
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
