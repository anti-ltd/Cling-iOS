/**
 Shared Dynamic Island compact + minimal layouts for sports pins. Compact regions
 are ~37pt tall — flag-only or single-line horizontal clusters; never stack text
 under icons (it clips). Minimal holds the glanceable stat.
 */
import SwiftUI

public enum SportsDICompact {
    /// Fits the compact Dynamic Island band without clipping.
    private static let flagSize: CGFloat = 20
    private static let scoreFont = Font.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit()
    private static let statFont = Font.system(size: 11, weight: .bold, design: .rounded).monospacedDigit()

    // MARK: - Match

    @ViewBuilder
    public static func matchLeading(_ m: MatchPayload, accent: Color) -> some View {
        scoreCluster(code: m.homeCode, score: m.homeScore, accent: accent, leading: true)
    }

    @ViewBuilder
    public static func matchTrailing(_ m: MatchPayload, accent: Color) -> some View {
        scoreCluster(code: m.awayCode, score: m.awayScore, accent: accent, leading: false)
    }

    @ViewBuilder
    public static func matchMinimal(_ m: MatchPayload, accent: Color) -> some View {
        switch m.status {
        case .scheduled, .finished:
            Text(m.scoreText)
                .font(statFont)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .live:
            HStack(spacing: 3) {
                LiveStatusDot(match: m, playingColor: accent, size: 5)
                // Self-ticking clock so the minute advances between pushes;
                // falls back to the static "47'" for hand-made matches.
                (SportsLockScreen.liveClockText(m) ?? Text(m.minute.map { "\($0)'" } ?? "LIVE"))
                    .font(statFont)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        case .halftime:
            phaseLabel("HT", tint: .orange)
        case .suspended:
            phaseLabel("SUSP", tint: .orange)
        }
    }

    // MARK: - Game

    @ViewBuilder
    public static func gameLeading(_ g: TeamGamePayload, accent: Color) -> some View {
        abbrScoreCluster(abbr: g.homeAbbr, score: g.homeScore, accent: accent, leading: true)
    }

    @ViewBuilder
    public static func gameTrailing(_ g: TeamGamePayload, accent: Color) -> some View {
        abbrScoreCluster(abbr: g.awayAbbr, score: g.awayScore, accent: accent, leading: false)
    }

    @ViewBuilder
    public static func gameMinimal(_ g: TeamGamePayload, accent: Color) -> some View {
        switch g.status {
        case .scheduled, .finished:
            Text(g.scoreText)
                .font(statFont)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .live:
            HStack(spacing: 3) {
                LiveStatusDot(game: g, playingColor: accent, size: 5)
                Text(g.statusLine())
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        case .halftime:
            phaseLabel("Half", tint: .orange)
        }
    }

    // MARK: - Pieces

    private static func flagOnly(_ code: String) -> some View {
        FlagImage(code, size: flagSize, ringed: true)
    }

    private static func scoreCluster(code: String, score: Int, accent: Color, leading: Bool) -> some View {
        HStack(spacing: 3) {
            if leading {
                flagOnly(code)
                Text("\(score)")
                    .font(scoreFont)
                    .foregroundStyle(accent)
            } else {
                Text("\(score)")
                    .font(scoreFont)
                    .foregroundStyle(accent)
                flagOnly(code)
            }
        }
    }

    private static func abbrOnly(_ abbr: String) -> some View {
        Text(abbr)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .lineLimit(1)
    }

    private static func abbrScoreCluster(abbr: String, score: Int, accent: Color, leading: Bool) -> some View {
        HStack(spacing: 3) {
            if leading {
                abbrOnly(abbr)
                Text("\(score)")
                    .font(scoreFont)
                    .foregroundStyle(accent)
            } else {
                Text("\(score)")
                    .font(scoreFont)
                    .foregroundStyle(accent)
                abbrOnly(abbr)
            }
        }
    }

    private static func phaseLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(statFont)
            .foregroundStyle(tint)
    }
}
