/**
 A round flag badge for a FIFA code.

 World Cup match pins carry their teams as FIFA codes (no image can ride the 4KB
 Live Activity push — see `MatchPayload`). The flag art is therefore bundled and
 looked up client-side here: an imageset named `flag-<CODE>` in
 `Resources/Flags.xcassets`, compiled into every target that renders a match
 (app, widget, share). Rectangular source art is filled into a circle to match
 the badge style; an unmapped code falls back to the flag emoji so a nation we
 haven't bundled still renders.
 */
import SwiftUI

public struct FlagImage: View {
    private let code: String
    private let size: CGFloat
    private let ringed: Bool

    public init(_ fifaCode: String, size: CGFloat, ringed: Bool = true) {
        self.code = MatchPayload.normalizeCode(fifaCode)
        self.size = size
        self.ringed = ringed
    }

    public var body: some View {
        if FlagAsset.has(code) {
            Image("flag-\(code)")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    if ringed {
                        Circle().strokeBorder(.white.opacity(0.65),
                                              lineWidth: max(0.5, size * 0.045))
                    }
                }
                .shadow(color: .black.opacity(0.18), radius: size * 0.05, y: size * 0.02)
        } else {
            // No bundled art — fall back to the emoji glyph at a matching size.
            Text(MatchPayload.flag(for: code))
                .font(.system(size: size * 0.92))
                .frame(width: size, height: size)
        }
    }
}

enum FlagAsset {
    /// FIFA codes with bundled round-flag artwork — the World Cup roster. Stays
    /// in lockstep with `Resources/Flags.xcassets`; add the imageset and the
    /// nation lands here automatically (the catalog is generated from this set).
    static let available: Set<String> = Set(LeagueTeams.worldCup.map(\.abbr))

    static func has(_ code: String) -> Bool { available.contains(code) }
}
