/**
 `MatchPushUploader`: Cling's half of the closed-app live score, now roster-
 shaped. Cling runs ONE Live Activity carrying every pinned thing, so the device
 registers ONE subscription with the server:

 - the **roster activity's update token** (from `PushTokenStore`),
 - the full **content-state template** — the exact JSON the system will decode,
   built by `ActivityPushContract` from every live pin, and
 - the list of **sport elements** inside it (pinID + typeID + sourceID + league).
   The server polls each league, and when a score changes it mutates only the
   matching element inside the template (by sourceID) and re-pushes the WHOLE
   content state to the roster token — local pins (note/parking/decor) ride
   along untouched, so a push never blanks them.

 Wired to `PushToStartRegistrar.onTokensChanged` and called after a pin changes.
 Best-effort: a failed upload just means the foreground poller carries the score
 until the next sync.
 */
import Foundation

@MainActor
final class MatchPushUploader {
    /// The anti.ltd Worker route (deployed from `server/`).
    static let endpoint = URL(string: "https://cling-push.snow-whitehouse.workers.dev/register")!

    private let store = ClingStore.shared
    private let tokens = PushTokenStore.shared

    /// A stable per-install id so the server can replace a device's whole
    /// registration on each sync rather than accumulating stale rows.
    private static let deviceID: String = {
        let key = "cling-device-id"
        let defaults = UserDefaults(suiteName: ClingKit.appGroupID) ?? .standard
        if let existing = defaults.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }()

    /// Register the device's current roster with the server. Sends even when
    /// nothing's tracked so the server can clear a device that unpinned its last
    /// sport pin. No-ops only when there's nothing to authenticate against (no
    /// roster or push-to-start token yet).
    func sync() {
        let current = tokens.load()
        let settings = store.loadSettings()
        let pins = store.loadPins().filter { $0.status != .ended }
        let staleDate = Date(timeIntervalSinceNow: 8 * 3600 - 60)

        // The server pushes this whole content-state back to the device, so it
        // must obey the same ~4 KB ceiling the in-process path does — an oversized
        // roster is silently dropped and the closed-app card renders empty. Order
        // the live-sport/ticker pins (the ones the server actually mutates and
        // must keep) first, then trim the tail to fit.
        let liveSportTypes: Set<PinTypeID> = [.match, .fight, .game, .ticker]
        let ordered = pins.sorted { liveSportTypes.contains($0.typeID) && !liveSportTypes.contains($1.typeID) }
        let snapshots = ActivityPushContract.fitToBudget(
            ordered.map { $0.snapshot(staleDate: staleDate) })

        // Source id + league identify which feed the server polls; the type
        // tells it which payload fields to swap. Both live-sport types ride the
        // same path.
        let sports: [SportElement] = pins.compactMap { pin in
            let sport: (sourceID: String, league: String)?
            switch pin.payload {
            case .match(let m): sport = m.sourceID.map { ($0, m.league) }
            case .fight(let f): sport = f.sourceID.map { ($0, f.league) }
            case .game(let g):  sport = g.sourceID.map { ($0, g.league) }
            // Tickers have no ESPN league — the sentinel "ticker" tells the
            // server to resolve via the quote API; sourceID = market:symbol.
            case .ticker(let t): sport = t.sourceID.map { ($0, "ticker") }
            default:            sport = nil
            }
            return sport.map {
                SportElement(
                    pinID: pin.id.uuidString,
                    typeID: pin.typeID.rawValue,
                    sourceID: $0.sourceID,
                    league: $0.league)
            }
        }

        // Nothing to track over a live token, and no push-to-start token to seed
        // a closed-app start — don't bother the server.
        let canUpdate = !sports.isEmpty && current.rosterUpdateToken != nil
        guard canUpdate || current.pushToStart != nil else { return }

        let body = RegisterRequest(
            deviceID: Self.deviceID,
            pushToStart: current.pushToStart,
            bundleID: ActivityPushContract.apnsTopic,
            rosterToken: current.rosterUpdateToken,
            contentState: ActivityPushContract.referenceContentStateJSON(for: snapshots, staleDate: staleDate),
            attributes: ActivityPushContract.referenceAttributesJSON(),
            sports: sports,
            // Tells the server whether/how a fresh commentary line should alert
            // (and so momentarily expand the island) on a closed-app push.
            commentaryAlerts: settings.matchPlayByPlay ? settings.matchCommentaryAlerts.rawValue : "off",
            commentaryAlertSound: settings.matchCommentaryAlertSound)

        guard let data = try? JSONEncoder().encode(body) else { return }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        Task.detached {
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    // MARK: Wire shape (mirrors the Worker's RegisterRequest)

    private struct RegisterRequest: Codable {
        let deviceID: String
        let pushToStart: String?
        let bundleID: String
        /// The roster activity's update token — what the server pushes refreshed
        /// content state to. Nil until the activity mints one.
        let rosterToken: String?
        /// Full roster content-state JSON, as a string the server JSON-parses,
        /// mutates in place, and re-pushes.
        let contentState: String
        /// Roster attributes JSON (for a future push-to-start), as a string.
        let attributes: String
        /// Which elements inside `contentState.pins` are server-tracked.
        let sports: [SportElement]
        /// Commentary auto-expand preference: "off" | "important" | "all".
        let commentaryAlerts: String
        /// Whether a commentary auto-expand also pings (sound + haptic).
        let commentaryAlertSound: Bool
    }

    private struct SportElement: Codable {
        let pinID: String
        /// "match" | "fight" — tells the server which payload fields to swap.
        let typeID: String
        let sourceID: String
        /// ESPN scoreboard path the server polls for this element.
        let league: String
    }
}
