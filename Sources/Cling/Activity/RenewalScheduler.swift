/**
 The re-arm strategy's notification half. iOS caps a Live Activity at 8h, and
 only the app can start a new one — so shortly before a renewable pin goes
 stale, a local notification offers to keep it alive. Tapping it (or its
 "Keep pinned" action) opens the app, which re-requests the activity and
 reschedules. Pins the user foregrounds the app for renew silently without
 ever seeing the notification (see `AppModel.renewExpiringPins`).
 */
import Foundation
import UserNotifications

@MainActor
final class RenewalScheduler {
    static let categoryID = "PIN_RENEWAL"
    static let keepPinnedActionID = "KEEP_PINNED"
    /// How long before staleness the nudge lands.
    static let leadTime: TimeInterval = 15 * 60

    private let center = UNUserNotificationCenter.current()
    private var authorizationRequested = false

    func registerCategory() {
        let keep = UNNotificationAction(
            identifier: Self.keepPinnedActionID,
            title: "Keep pinned",
            options: [.foreground])  // renewal requires the app process
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [keep],
            intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    /// Schedule the "expires soon" nudge for a freshly-(re)activated pin.
    /// Replaces any previous schedule for the same pin.
    func scheduleRenewal(for pin: Pin) {
        guard let staleDate = pin.staleDate, pin.isRenewable else { return }
        let fireDate = staleDate.addingTimeInterval(-Self.leadTime)
        guard fireDate > .now else { return }

        Task {
            await requestAuthorizationIfNeeded()

            let content = UNMutableNotificationContent()
            content.title = "Pin expiring soon"
            content.body = body(for: pin)
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            content.userInfo = ["pinID": pin.id.uuidString]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(60, fireDate.timeIntervalSinceNow),
                repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.requestID(for: pin.id),
                content: content,
                trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelRenewal(for pinID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID(for: pinID)])
    }

    private static func requestID(for pinID: UUID) -> String {
        "renewal-\(pinID.uuidString)"
    }

    private func body(for pin: Pin) -> String {
        switch pin.payload {
        case .parking: "Your parking pin is about to leave the Dynamic Island. Tap to keep it alive."
        case .note:    "Your note is about to leave the Dynamic Island. Tap to keep it alive."
        case .timer:   "Your timer outlives the 8-hour pin limit. Tap to keep it counting."
        case .decor:   "Your decoration is about to leave the Dynamic Island. Tap to keep it up."
        }
    }

    private func requestAuthorizationIfNeeded() async {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }
}

/// Routes notification taps back into pin renewal. UNUserNotificationCenter
/// holds its delegate weakly — `AppModel` owns this for the app's lifetime.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main actor with the pin to renew.
    var onRenew: (@MainActor (UUID) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let raw = userInfo["pinID"] as? String, let pinID = UUID(uuidString: raw) else { return }
        // Default tap and the explicit "Keep pinned" action both renew —
        // the notification exists for exactly one purpose.
        let handler = onRenew
        await MainActor.run { handler?(pinID) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // If the user is already in the app, foreground renewal has happened;
        // showing the banner anyway would be noise.
        []
    }
}
