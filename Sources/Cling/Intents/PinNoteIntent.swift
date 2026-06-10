/**
 "Pin a note" from Shortcuts, Spotlight, Siri, or the Action Button.
 `LiveActivityIntent` (iOS 17.2+) runs in the app's process and may start
 activities without foregrounding the app — the whole reason Cling's floor
 is 17.2.
 */
import AppIntents

struct PinNoteIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Pin a Note"
    static let description = IntentDescription(
        "Pins a short note to your Dynamic Island and lock screen.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Pin \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $text.needsValueError("What should the note say?")
        }
        let pin = await PinService.createAndActivate(.note(NotePayload(text: trimmed)))
        return .result(dialog: pin.status == .live
            ? "Pinned to your Dynamic Island."
            : "Saved — open Cling to pin it.")
    }
}
