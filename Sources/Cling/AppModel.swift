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
            // The push server reads the commentary auto-expand prefs from the
            // device's registration, not the pin store — and settings changes
            // touch neither pins nor tokens, so nothing else re-registers. Sync
            // explicitly when one of the server-visible prefs changes.
            if settings.matchCommentaryAlerts != oldValue.matchCommentaryAlerts
                || settings.matchCommentaryAlertSound != oldValue.matchCommentaryAlertSound
                || settings.matchPlayByPlay != oldValue.matchPlayByPlay {
                matchPush.sync()
            }
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
    /// Uploads pinned-match subscriptions so the server can push live scores
    /// while Cling is closed (Phase 3 of the World Cup feature).
    private let matchPush = MatchPushUploader()
    /// Held for the app's lifetime; fires when another process (the share
    /// extension) writes pins.
    private var pinsToken: AnyObject?

    init() {
        var loadedSettings = store.loadSettings()
        if loadedSettings.globalStyle != .default {
            let legacyStyle = loadedSettings.globalStyle
            loadedSettings.foldGlobalStyleIntoDefaults()
            settings = loadedSettings
            store.saveSettings(loadedSettings)
            var loadedPins = coordinator.reconcile(store.loadPins())
            for i in loadedPins.indices {
                loadedPins[i].appearance = legacyStyle.apply(to: loadedPins[i].appearance)
            }
            pins = loadedPins
            store.savePins(loadedPins, notify: false)
        } else {
            settings = loadedSettings
            pins = coordinator.reconcile(store.loadPins())
        }
        persist()
        pinsToken = store.observePins { [weak self] in
            Task { @MainActor in self?.reloadPins() }
        }
        coordinator.watchRoster { [weak self] status in
            self?.applyRosterState(status)
        }
        renewals.registerCategory()
        notificationRouter.onRenew = { [weak self] pinID in
            Task { await self?.activate(pinID: pinID) }
        }
        UNUserNotificationCenter.current().delegate = notificationRouter
        // Start collecting push tokens and upload match subscriptions whenever a
        // token lands (the roster activity's update token arrives here).
        pushRegistrar.onTokensChanged = { [weak self] _ in
            self?.matchPush.sync()
        }
        pushRegistrar.start()
        reapOrphanedPhotos()
        resyncRoster()
    }

    /// Re-read the shared store — after a Darwin change notification or a
    /// scene foreground (the share extension may have added a pending pin).
    func reloadPins() {
        pins = coordinator.reconcile(store.loadPins())
        persist()
    }

    /// Bring the roster activity in line after a foreground: pull any store
    /// changes the share extension made, then rebuild the activity — restarting
    /// it (resetting the 8 h ceiling) if anything's close to going stale. Most
    /// renewals happen here, invisibly; the notification only fires for pins the
    /// user never came back for.
    func foregroundSync() {
        reloadPins()
        resyncRoster(restart: coordinator.rosterNeedsRenewal(pins))
    }

    /// Rebuild the single roster activity from the current pin set and persist
    /// the outcome. `restart` resets the activity's ceiling (renewal).
    func resyncRoster(restart: Bool = false) {
        Task { await syncRosterNow(restart: restart) }
    }

    private func syncRosterNow(restart: Bool) async {
        let updated = await coordinator.syncRoster(pins, restart: restart)
        apply(roster: updated)
    }

    /// Adopt the coordinator's reconciled pin set and (re)arm the per-pin
    /// renewal nudges so a pin the user never returns for still warns.
    private func apply(roster updated: [Pin]) {
        pins = updated
        persist()
        for pin in pins {
            renewals.cancelRenewal(for: pin.id)
            if pin.status == .live, settings.renewalRemindersEnabled {
                renewals.scheduleRenewal(for: pin)
            }
        }
    }

    /// A specific pin asked to be (re)pinned — a renewal tap or an `activate`
    /// deep link. Un-end it if needed and restart the roster so its ceiling
    /// resets.
    func activate(pinID: UUID) async {
        if let i = pins.firstIndex(where: { $0.id == pinID }), pins[i].status == .ended {
            pins[i].status = .pending
        }
        await syncRosterNow(restart: true)
    }

    /// The coordinator observed the system aging out or dismissing the roster
    /// activity — reflect that on every pin that thought it was live.
    private func applyRosterState(_ status: PinStatus) {
        guard status != .live else { return }
        var changed = false
        for i in pins.indices where pins[i].status == .live {
            pins[i].status = status
            pins[i].activityID = nil
            changed = true
        }
        if changed { persist() }
    }

    // MARK: - Pin CRUD

    /// Pins visible in the main list (everything not fully ended).
    var activePins: [Pin] {
        pins.filter { $0.status != .ended }
            .sorted {
                ($0.payload.scheduledStart ?? $0.createdAt)
                    < ($1.payload.scheduledStart ?? $1.createdAt)
            }
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
        resyncRoster()
        return pin
    }

    // MARK: - Live sports pins (World Cup score, UFC card)

    /// Pin a match from the feed, or surface the one already pinned for it —
    /// the same fixture shouldn't take two slots in the island.
    @discardableResult
    func pinMatch(_ match: MatchPayload) -> Pin {
        if let id = match.sourceID,
           let existing = matchPin(forSource: id) {
            return existing
        }
        let pin = createPin(payload: .match(match))
        // The update token may already be parked; sync now so the server learns
        // about it without waiting for a token rotation.
        matchPush.sync()
        return pin
    }

    /// Pin a UFC card from the feed, or surface the one already pinned.
    @discardableResult
    func pinFight(_ fight: FightPayload) -> Pin {
        if let id = fight.sourceID, let existing = fightPin(forSource: id) {
            return existing
        }
        let pin = createPin(payload: .fight(fight))
        matchPush.sync()
        return pin
    }

    /// Pin a team game from the feed, or surface the one already pinned. Dresses
    /// the pin with the league's own glyph (basketball / puck / …).
    @discardableResult
    func pinGame(_ game: TeamGamePayload) -> Pin {
        if let id = game.sourceID, let existing = gamePin(forSource: id) {
            return existing
        }
        var appearance = settings.defaultAppearance(for: .game)
        if let league = SportLeague.allCases.first(where: { $0.path == game.league }) {
            appearance.symbolName = league.systemImage
        }
        let pin = createPin(payload: .game(game), appearance: appearance)
        matchPush.sync()
        return pin
    }

    private func matchPin(forSource id: String) -> Pin? {
        pins.first {
            if case .match(let m) = $0.payload { return m.sourceID == id }
            return false
        }
    }
    private func fightPin(forSource id: String) -> Pin? {
        pins.first {
            if case .fight(let f) = $0.payload { return f.sourceID == id }
            return false
        }
    }
    private func gamePin(forSource id: String) -> Pin? {
        pins.first {
            if case .game(let g) = $0.payload { return g.sourceID == id }
            return false
        }
    }

    /// While Cling is foreground, pull fresh state for every pinned live-sport
    /// pin and re-push the ones that changed. The open-app path; the push server
    /// carries the island when Cling is closed. One fetch per sport that's
    /// actually pinned; re-pushes only on a real change, to spare the budget.
    func refreshLiveSports() async {
        // Apply every score change to the pin set first, then rebuild the roster
        // activity once — one content update carries all of them, not one per pin.
        let matchesChanged = await refreshLiveMatches()
        let fightsChanged = await refreshLiveFights()
        let gamesChanged = await refreshLiveGames()
        guard matchesChanged || fightsChanged || gamesChanged else { return }
        persist()
        await syncRosterNow(restart: false)
    }

    @discardableResult
    private func refreshLiveMatches() async -> Bool {
        let tracked: [(UUID, MatchPayload)] = pins.compactMap { pin in
            guard case .match(let m) = pin.payload, m.sourceID != nil,
                  m.status != .finished else { return nil }
            return (pin.id, m)
        }
        guard !tracked.isEmpty, let feed = try? await MatchFeed.fetch() else { return false }
        let byID = Dictionary(feed.compactMap { p in p.sourceID.map { ($0, p) } },
                              uniquingKeysWith: { a, _ in a })
        var changedAny = false
        for (pinID, old) in tracked {
            guard let id = old.sourceID, let fresh = byID[id] else { continue }
            let changed = fresh.homeScore != old.homeScore
                || fresh.awayScore != old.awayScore
                || fresh.status != old.status
                || fresh.minute != old.minute
            guard changed, let i = pins.firstIndex(where: { $0.id == pinID }) else { continue }
            pins[i].payload = .match(old.updatingScore(
                homeScore: fresh.homeScore, awayScore: fresh.awayScore,
                minute: fresh.minute, status: fresh.status))
            changedAny = true
        }
        return changedAny
    }

    @discardableResult
    private func refreshLiveFights() async -> Bool {
        let tracked: [(UUID, FightPayload)] = pins.compactMap { pin in
            guard case .fight(let f) = pin.payload, f.sourceID != nil,
                  f.status != .finished else { return nil }
            return (pin.id, f)
        }
        guard !tracked.isEmpty, let feed = try? await FightFeed.fetch() else { return false }
        let byID = Dictionary(feed.compactMap { p in p.sourceID.map { ($0, p) } },
                              uniquingKeysWith: { a, _ in a })
        var changedAny = false
        for (pinID, old) in tracked {
            guard let id = old.sourceID, let fresh = byID[id] else { continue }
            let changed = fresh.redName != old.redName || fresh.blueName != old.blueName
                || fresh.round != old.round || fresh.clock != old.clock
                || fresh.status != old.status || fresh.winner != old.winner
                || fresh.boutName != old.boutName
            guard changed, let i = pins.firstIndex(where: { $0.id == pinID }) else { continue }
            pins[i].payload = .fight(old.updatingBout(
                redName: fresh.redName, blueName: fresh.blueName,
                round: fresh.round, clock: fresh.clock, boutName: fresh.boutName,
                status: fresh.status, winner: fresh.winner, method: fresh.method))
            changedAny = true
        }
        return changedAny
    }

    @discardableResult
    private func refreshLiveGames() async -> Bool {
        let tracked: [(UUID, TeamGamePayload)] = pins.compactMap { pin in
            guard case .game(let g) = pin.payload, g.sourceID != nil,
                  g.status != .finished else { return nil }
            return (pin.id, g)
        }
        guard !tracked.isEmpty else { return false }
        // Games span several leagues — one fetch per distinct league pinned.
        var byID: [String: TeamGamePayload] = [:]
        for league in Set(tracked.map(\.1.league)) {
            guard let feed = try? await GameFeed.fetch(leaguePath: league) else { continue }
            for p in feed { if let id = p.sourceID { byID[id] = p } }
        }
        guard !byID.isEmpty else { return false }
        var changedAny = false
        for (pinID, old) in tracked {
            guard let id = old.sourceID, let fresh = byID[id] else { continue }
            let changed = fresh.homeScore != old.homeScore || fresh.awayScore != old.awayScore
                || fresh.period != old.period || fresh.clock != old.clock
                || fresh.situation != old.situation || fresh.status != old.status
            guard changed, let i = pins.firstIndex(where: { $0.id == pinID }) else { continue }
            pins[i].payload = .game(old.updatingState(
                homeScore: fresh.homeScore, awayScore: fresh.awayScore,
                period: fresh.period, clock: fresh.clock,
                situation: fresh.situation, status: fresh.status))
            changedAny = true
        }
        return changedAny
    }

    /// True while any pinned live-sport pin is still in play — the poll loop
    /// runs only when it's worth a network call.
    var hasLiveSportPins: Bool {
        pins.contains { pin in
            switch pin.payload {
            case .match(let m): return m.status != .finished
            case .fight(let f): return f.status != .finished
            case .game(let g):  return g.status != .finished
            default:            return false
            }
        }
    }

    /// Apply a content/appearance edit and push it into the live activity.
    /// Re-bakes the global house style so a per-pin accent/glyph edit can't
    /// drift the shared surface/type/density/border.
    func update(_ pin: Pin) {
        guard let i = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        pins[i] = pin
        persist()
        resyncRoster()
        // Re-register so server pushes carry the latest appearance (accent,
        // showsExpiry, …) instead of the template from when the pin was first
        // synced.
        matchPush.sync()
    }

    func delete(_ pin: Pin) {
        if let filename = photoFilename(of: pin.payload) {
            PhotoStore.shared.delete(filename)
        }
        pins.removeAll { $0.id == pin.id }
        persist()
        renewals.cancelRenewal(for: pin.id)
        // Rebuild the roster without this pin (and end the activity outright if
        // it was the last one).
        resyncRoster()
        // Tell the server the subscription set changed — otherwise it keeps
        // pushing updates that revive the island.
        matchPush.sync()
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
        case .timer, .decor, .match, .fight, .game, .ticker: nil
        }
    }
}
