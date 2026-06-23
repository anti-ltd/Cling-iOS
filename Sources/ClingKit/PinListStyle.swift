/**
 How a pin draws in the main list — compact when several are pinned, featured
 when a pin owns the board (solo pin or the one live fixture up top).
 */
import SwiftUI

public enum PinListStyle: Equatable, Sendable {
    case compact
    case featured
}

private struct PinListStyleKey: EnvironmentKey {
    static let defaultValue: PinListStyle = .compact
}

public extension EnvironmentValues {
    var pinListStyle: PinListStyle {
        get { self[PinListStyleKey.self] }
        set { self[PinListStyleKey.self] = newValue }
    }
}
