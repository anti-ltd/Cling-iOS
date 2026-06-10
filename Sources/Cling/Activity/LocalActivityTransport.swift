/**
 ActivityKit transport — `Activity.request` and friends, in-process. The only
 file in the app that touches ActivityKit directly.
 */
import Foundation
import ActivityKit

@MainActor
struct LocalActivityTransport: ActivityTransport {
    func start(_ pin: Pin, staleDate: Date) throws -> String {
        let attributes = ClingActivityAttributes(pinID: pin.id, typeID: pin.typeID)
        let state = ClingActivityAttributes.ContentState(
            payload: pin.payload, appearance: pin.appearance, staleDate: staleDate)
        let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(
                state: state,
                staleDate: staleDate,
                relevanceScore: relevance(of: pin)))
        return activity.id
    }

    func update(_ pin: Pin, staleDate: Date) async {
        let state = ClingActivityAttributes.ContentState(
            payload: pin.payload, appearance: pin.appearance, staleDate: staleDate)
        for activity in Activity<ClingActivityAttributes>.activities
        where activity.attributes.pinID == pin.id {
            await activity.update(ActivityContent(
                state: state,
                staleDate: staleDate,
                relevanceScore: relevance(of: pin)))
        }
    }

    func end(activityID: String, dismissal: PinDismissal) async {
        for activity in Activity<ClingActivityAttributes>.activities
        where activity.id == activityID {
            await activity.end(
                activity.content,
                dismissalPolicy: dismissal == .immediate ? .immediate : .default)
        }
    }

    func currentActivityIDs() -> [UUID: String] {
        Dictionary(
            Activity<ClingActivityAttributes>.activities.map { ($0.attributes.pinID, $0.id) },
            uniquingKeysWith: { first, _ in first })
    }

    /// With several pins live, iOS uses relevance to pick who gets the island.
    /// Timers (which have a deadline) outrank ambient pins, sooner deadlines
    /// outrank later ones.
    private func relevance(of pin: Pin) -> Double {
        guard let endDate = pin.endDate else { return 50 }
        let remaining = max(60, endDate.timeIntervalSinceNow)
        return 100 + 10_000 / remaining
    }
}
