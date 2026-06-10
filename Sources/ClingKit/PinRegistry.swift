/**
 The pin-type registry — the single place a new type plugs in.
 */
import Foundation

@MainActor
public enum PinRegistry {
    public static let modules: [PinTypeID: any PinModule.Type] = [
        .note: NotePinModule.self,
        .timer: TimerPinModule.self,
        .parking: ParkingPinModule.self,
        .clipboard: ClipboardPinModule.self,
    ]

    public static func module(for typeID: PinTypeID) -> any PinModule.Type {
        guard let module = modules[typeID] else {
            // Every PinTypeID case must be registered; an unregistered type is
            // a programmer error caught in the first manual run.
            fatalError("No PinModule registered for \(typeID.rawValue)")
        }
        return module
    }

    /// Modules in the order the quick-add type switcher offers them.
    public static var ordered: [any PinModule.Type] {
        PinTypeID.allCases.map { module(for: $0) }
    }
}
