/**
 "Pin my parking spot" — grab one location fix and pin it, no app, no typing.
 The Action Button use case: park, click, walk away.

 Location permission has to already exist: an intent running in the background
 can't reliably present the system prompt, so an undetermined state bounces to
 the foreground app (whose composer asks properly).
 */
import AppIntents
import CoreLocation

// ForegroundContinuableIntent supplies needsToContinueInForegroundError —
// the bounce used when location permission was never asked.
struct PinParkingSpotIntent: AppIntent, LiveActivityIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Pin Parking Spot"
    static let description = IntentDescription(
        "Remembers where you parked as a pin in your Dynamic Island and lock screen.")

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Pin my parking spot") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .notDetermined:
            // The app's composer can show the permission prompt; we can't.
            throw needsToContinueInForegroundError("Cling needs one-time location access — continue in the app to allow it.")
        default:
            throw IntentError.message("Location access is off for Cling. Enable it in Settings to pin parking spots.")
        }

        guard let fix = await oneShotFix() else {
            throw IntentError.message("Couldn't get a location fix. Try again with a clearer view of the sky.")
        }

        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = ParkingPayload(
            latitude: fix.latitude,
            longitude: fix.longitude,
            note: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        let pin = await PinService.createAndActivate(.parking(payload))
        return .result(dialog: pin.status == .live
            ? "Parking spot pinned."
            : "Spot saved — open Cling to pin it.")
    }

    private func oneShotFix() async -> CLLocationCoordinate2D? {
        await LocationFix.coordinate()
    }
}

/// A user-facing intent failure with a custom message.
enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case message(String)

    var localizedStringResource: LocalizedStringResource {
        if case .message(let text) = self { return "\(text)" }
        return "Something went wrong."
    }
}
