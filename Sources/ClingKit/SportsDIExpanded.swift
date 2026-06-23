/**
 Expanded Dynamic Island — sports pins render as one self-contained center panel.
 Splitting across leading/trailing/bottom regions is unreliable in ActivityKit.
 */
import SwiftUI

public enum SportsDIExpanded {
    public static func matchCenter(_ m: MatchPayload, accent: Color) -> some View {
        SportsLockScreen.matchExpandedPanel(m, accent: accent)
    }

    public static func gameCenter(_ g: TeamGamePayload, accent: Color) -> some View {
        SportsLockScreen.gameExpandedPanel(g, accent: accent)
    }

    // Side regions intentionally empty — the center panel carries the full layout.
    public static func emptyLeading() -> some View { EmptyView() }
    public static func emptyTrailing() -> some View { EmptyView() }
}
