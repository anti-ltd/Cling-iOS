/**
 "Start a countdown" from Shortcuts / Action Button — a timer pin without
 opening the app.
 */
import AppIntents

struct StartCountdownIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start a Countdown"
    static let description = IntentDescription(
        "Starts a countdown pinned to your Dynamic Island and lock screen.")

    @Parameter(title: "Minutes", default: 15, inclusiveRange: (1, 720))
    var minutes: Int

    @Parameter(title: "Label")
    var label: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Count down \(\.$minutes) minutes") {
            \.$label
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let payload = TimerPayload(
            label: label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            startDate: now,
            endDate: now.addingTimeInterval(TimeInterval(minutes * 60)))
        let pin = await PinService.createAndActivate(.timer(payload))
        return .result(dialog: pin.status == .live
            ? "Counting down \(minutes) minutes."
            : "Countdown saved — open Cling to pin it.")
    }
}
