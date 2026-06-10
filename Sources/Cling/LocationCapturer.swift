/**
 One-shot location fix for the parking pin. `CLLocationUpdate.liveUpdates`
 (iOS 17) prompts for When-In-Use on first call, yields until a usable fix
 arrives, and we stop right there — Cling never tracks.
 */
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationCapturer {
    enum State: Equatable {
        case idle
        case capturing
        case captured(latitude: Double, longitude: Double)
        case denied
        case failed
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    func capture() {
        guard state == .idle || state == .denied || state == .failed else { return }
        state = .capturing
        task?.cancel()
        task = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if Task.isCancelled { return }
                    if #available(iOS 18.0, *),
                       update.authorizationDenied || update.authorizationRestricted {
                        state = .denied
                        return
                    }
                    if let location = update.location {
                        state = .captured(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude)
                        return // one fix is the whole job
                    }
                }
            } catch {
                if !Task.isCancelled { state = .failed }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if state == .capturing { state = .idle }
    }
}
