/**
 Where Cling parks the APNs tokens a server needs to push Live Activities.

 Two kinds of token, both hex strings:

 - The **push-to-start** token (`Activity<…>.pushToStartTokenUpdates`, iOS 17.2+)
   — one per install. A server pushes to it to START a brand-new activity while
   Cling isn't running. This is what makes "Clink sends a note, it appears in
   the Dynamic Island without opening Cling" possible.
 - Per-activity **update** tokens (`activity.pushTokenUpdates`) — one per live
   pin. A server pushes to these to update or end an already-running activity.

 Stored as a JSON file in the App Group (same discipline as `ClingStore` — files
 not UserDefaults, see its note) so any process can read what to upload, and the
 token survives relaunches. A real deployment uploads these to the anti.ltd
 Worker; until that exists they just persist here, inert and ready.
 */
import Foundation

public struct PushTokens: Codable, Equatable, Sendable {
    /// Install-wide push-to-start token, hex. Nil until ActivityKit first
    /// hands one over (it can rotate — always use the latest).
    public var pushToStart: String?
    /// pinID → that activity's update token, hex. Pruned when a pin ends.
    public var updateTokens: [UUID: String]

    public init(pushToStart: String? = nil, updateTokens: [UUID: String] = [:]) {
        self.pushToStart = pushToStart
        self.updateTokens = updateTokens
    }
}

public final class PushTokenStore: @unchecked Sendable {
    /// Posted when any token changes — a token uploader observes this to sync
    /// the server.
    public static let tokensDidChangeNotification = "ltd.anti.cling.pushTokensDidChange"

    public static let shared = PushTokenStore()

    private let appGroupID: String
    private let lock = NSLock()

    public init(appGroupID: String = ClingKit.appGroupID) {
        self.appGroupID = appGroupID
    }

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("cling-push.v1.json")
    }

    public func load() -> PushTokens {
        lock.lock(); defer { lock.unlock() }
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PushTokens.self, from: data) {
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: "cling-push-v1"),
           let decoded = try? JSONDecoder().decode(PushTokens.self, from: data) {
            return decoded
        }
        return PushTokens()
    }

    private func save(_ tokens: PushTokens) {
        lock.lock(); defer { lock.unlock() }
        if let url = fileURL, let data = try? JSONEncoder().encode(tokens) {
            try? data.write(to: url, options: .atomic)
        } else if let data = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(data, forKey: "cling-push-v1")
        }
        post(Self.tokensDidChangeNotification)
    }

    /// Record the latest install-wide push-to-start token. No-op (no
    /// notification) when unchanged, so repeated identical updates from the
    /// token stream don't churn the uploader.
    public func setPushToStart(_ token: String) {
        var t = load()
        guard t.pushToStart != token else { return }
        t.pushToStart = token
        save(t)
    }

    public func setUpdateToken(_ token: String, for pinID: UUID) {
        var t = load()
        guard t.updateTokens[pinID] != token else { return }
        t.updateTokens[pinID] = token
        save(t)
    }

    public func removeUpdateToken(for pinID: UUID) {
        var t = load()
        guard t.updateTokens[pinID] != nil else { return }
        t.updateTokens[pinID] = nil
        save(t)
    }

    public func observe(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        TokenWatch(name: Self.tokensDidChangeNotification, handler: handler)
    }

    private func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// Same retain-the-closure trick as `ClingStore`'s token — CFNotificationCenter
/// holds only a raw pointer, so this object owns the Swift closure and
/// unregisters on dealloc.
private final class TokenWatch: @unchecked Sendable {
    let handler: @Sendable () -> Void
    init(name: String, handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<TokenWatch>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            name as CFString, nil, .deliverImmediately)
    }
    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque())
    }
}
