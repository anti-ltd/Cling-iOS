/**
 App Shortcuts: the three intents, registered with natural phrases so they
 surface in Spotlight, Siri, and the Action Button picker with zero setup.
 */
import AppIntents

struct ClingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PinNoteIntent(),
            phrases: [
                "Pin a note in \(.applicationName)",
                "\(.applicationName) a note",
            ],
            shortTitle: "Pin a Note",
            systemImageName: "note.text")
        AppShortcut(
            intent: StartCountdownIntent(),
            phrases: [
                "Start a countdown in \(.applicationName)",
                "Start a \(.applicationName) timer",
            ],
            shortTitle: "Start Countdown",
            systemImageName: "timer")
        AppShortcut(
            intent: PinParkingSpotIntent(),
            phrases: [
                "Pin my parking spot in \(.applicationName)",
                "Remember where I parked with \(.applicationName)",
            ],
            shortTitle: "Pin Parking Spot",
            systemImageName: "car.fill")
    }
}
