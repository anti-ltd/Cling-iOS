/**
 One-shot location fix for the parking pin. Uses `CLLocationManager.requestLocation`
 — a single fix, not live updates — so the status-bar arrow clears as soon as the
 coordinate arrives. Cling never tracks.
 */
import CoreLocation
import Observation

/// Shared one-shot lookup for the parking composer and the pin-parking intent.
@MainActor
enum LocationFix {
    static func coordinate() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            OneShotLocator.shared.locate { continuation.resume(returning: $0) }
        }
    }

    static var isDenied: Bool {
        switch OneShotLocator.shared.authorizationStatus {
        case .denied, .restricted: true
        default: false
        }
    }
}

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
            let coordinate = await LocationFix.coordinate()
            if Task.isCancelled { return }
            if let coordinate {
                state = .captured(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude)
            } else {
                state = LocationFix.isDenied ? .denied : .failed
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        OneShotLocator.shared.cancel()
        if state == .capturing { state = .idle }
    }
}

// MARK: - One-shot CLLocationManager

@MainActor
private final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    static let shared = OneShotLocator()

    private let manager = CLLocationManager()
    private var handler: ((CLLocationCoordinate2D?) -> Void)?

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func locate(_ handler: @escaping (CLLocationCoordinate2D?) -> Void) {
        cancel()
        self.handler = handler
        switch manager.authorizationStatus {
        case .denied, .restricted:
            finish(nil)
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        @unknown default:
            finish(nil)
        }
    }

    func cancel() {
        handler = nil
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        let handler = handler
        self.handler = nil
        handler?(coordinate)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            finish(locations.last?.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard handler != nil else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                finish(nil)
            default:
                break
            }
        }
    }
}
