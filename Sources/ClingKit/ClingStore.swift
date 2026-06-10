/**
 `ClingStore`: the inter-process bridge. The app, widget extension, and share
 extension share pins and settings through JSON **files** in the App Group
 container — NOT App Group `UserDefaults`, whose cross-process reads are cached
 per-process by cfprefsd and go stale (the lesson learned in Clink). A fresh
 `Data(contentsOf:)` always reflects the latest bytes on disk.

 A Darwin notification is posted on save so a running sibling process can react
 immediately — the app sweeps pending pins the share extension just wrote.
 */
import Foundation

public final class ClingStore: @unchecked Sendable {
    /// Darwin notification posted whenever the pin list changes.
    public static let pinsDidChangeNotification = "ltd.anti.cling.pinsDidChange"
    /// Darwin notification posted whenever settings change.
    public static let settingsDidChangeNotification = "ltd.anti.cling.settingsDidChange"

    public static let shared = ClingStore()

    private let appGroupID: String

    public init(appGroupID: String = ClingKit.appGroupID) {
        self.appGroupID = appGroupID
    }

    private func containerURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    // MARK: - Pins

    /// `…/<AppGroup>/cling-pins.v1.json`
    private var pinsFileURL: URL? {
        containerURL()?.appendingPathComponent("cling-pins.v1.json")
    }

    public func loadPins() -> [Pin] {
        if let url = pinsFileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Pin].self, from: data) {
            return decoded
        }
        // App Group container unavailable (self-signed build without a matching
        // provisioning profile). Fall back to standard UserDefaults so pins at
        // least survive within this process rather than resetting every time.
        if let data = UserDefaults.standard.data(forKey: "cling-pins-v1"),
           let decoded = try? JSONDecoder().decode([Pin].self, from: data) {
            return decoded
        }
        return []
    }

    /// Persist the full pin list. `notify` posts the cross-process change
    /// notification; pass `false` for self-originated writes where the writer
    /// already updated its own live state and a reload would only churn.
    public func savePins(_ pins: [Pin], notify: Bool = true) {
        if let url = pinsFileURL,
           let data = try? JSONEncoder().encode(pins) {
            try? data.write(to: url, options: .atomic)
            if notify { post(Self.pinsDidChangeNotification) }
            return
        }
        if let data = try? JSONEncoder().encode(pins) {
            UserDefaults.standard.set(data, forKey: "cling-pins-v1")
        }
    }

    /// Read-modify-write convenience for a single pin.
    public func upsert(_ pin: Pin, notify: Bool = true) {
        var pins = loadPins()
        if let i = pins.firstIndex(where: { $0.id == pin.id }) {
            pins[i] = pin
        } else {
            pins.append(pin)
        }
        savePins(pins, notify: notify)
    }

    // MARK: - Settings

    /// `…/<AppGroup>/cling-settings.v1.json`
    private var settingsFileURL: URL? {
        containerURL()?.appendingPathComponent("cling-settings.v1.json")
    }

    public func loadSettings() -> ClingSettings {
        if let url = settingsFileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(ClingSettings.self, from: data) {
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: "cling-settings-v1"),
           let decoded = try? JSONDecoder().decode(ClingSettings.self, from: data) {
            return decoded
        }
        return .default
    }

    public func saveSettings(_ settings: ClingSettings, notify: Bool = true) {
        if let url = settingsFileURL,
           let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: url, options: .atomic)
            if notify { post(Self.settingsDidChangeNotification) }
            return
        }
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "cling-settings-v1")
        }
    }

    // MARK: - Cross-process change notifications

    private func post(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }

    /// Register a callback fired when pins change in another process. Keep the
    /// returned token alive for as long as you want the callback; releasing it
    /// automatically unregisters.
    public func observePins(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        NotificationToken(name: Self.pinsDidChangeNotification, handler: handler)
    }

    public func observeSettings(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        NotificationToken(name: Self.settingsDidChangeNotification, handler: handler)
    }

    public func stopObserving(_ token: AnyObject) {
        (token as? NotificationToken)?.unregister()
    }
}

/// Retains the Swift closure for the lifetime of a Darwin notification
/// registration (CFNotificationCenter only stores a raw pointer) and removes
/// the observer when it deallocates — so the caller just has to hold/drop it.
private final class NotificationToken: @unchecked Sendable {
    let handler: @Sendable () -> Void

    init(name: String, handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center, observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<NotificationToken>.fromOpaque(observer)
                    .takeUnretainedValue().handler()
            },
            name as CFString, nil, .deliverImmediately
        )
    }

    func unregister() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { unregister() }
}
