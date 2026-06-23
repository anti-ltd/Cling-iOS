/**
 Lock-screen and expanded Dynamic Island layouts for sports pins. Live Activity
 views need explicit column widths — flexible HStacks collapse to a single
 corner in the widget process.
 */
import SwiftUI

public enum SportsLockScreen {
    // MARK: - Full cards

    /// The lock-screen Live Activity banner for a football match.
    public static func matchCard(_ m: MatchPayload, accent: Color, compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            matchRow(m, accent: accent, compact: compact)
            matchFooter(m, accent: accent, compact: compact)
        }
        .frame(maxWidth: .infinity)
    }

    /// The lock-screen banner for a US-league game.
    public static func gameCard(_ g: TeamGamePayload, accent: Color, compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            gameRow(g, accent: accent, compact: compact)
            gameFooter(g, accent: accent, compact: compact)
        }
        .frame(maxWidth: .infinity)
    }

    /// Everything for an expanded Dynamic Island — one panel in the center region.
    public static func matchExpandedPanel(_ m: MatchPayload, accent: Color) -> some View {
        VStack(spacing: 6) {
            matchRow(m, accent: accent, compact: true)
            matchFooter(m, accent: accent, compact: true)
        }
        .frame(maxWidth: .infinity)
    }

    public static func gameExpandedPanel(_ g: TeamGamePayload, accent: Color) -> some View {
        VStack(spacing: 6) {
            gameRow(g, accent: accent, compact: true)
            gameFooter(g, accent: accent, compact: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Match row

    private static func rowInset(compact: Bool) -> CGFloat {
        compact ? 8 : 12
    }

    private static func matchRow(_ m: MatchPayload, accent: Color, compact: Bool) -> some View {
        let flagSize: CGFloat = compact ? 28 : 36
        let inset = rowInset(compact: compact)
        return VStack(spacing: compact ? 3 : 4) {
            // Flags share a row with the score so they stay vertically centred together.
            HStack(alignment: .center, spacing: 0) {
                FlagImage(m.homeCode, size: flagSize, ringed: true)
                    .padding(.leading, inset)
                Spacer(minLength: 6)
                scoreCenter(m.scoreText, accent: accent, compact: compact)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                FlagImage(m.awayCode, size: flagSize, ringed: true)
                    .padding(.trailing, inset)
            }
            // Codes sit below, each centred under its flag column.
            HStack(alignment: .top, spacing: 0) {
                teamCodeLabel(code: m.homeCode, flagSize: flagSize, compact: compact)
                    .padding(.leading, inset)
                Spacer(minLength: 6)
                Spacer(minLength: 6)
                teamCodeLabel(code: m.awayCode, flagSize: flagSize, compact: compact)
                    .padding(.trailing, inset)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static func teamCodeLabel(code: String, flagSize: CGFloat, compact: Bool) -> some View {
        Text(code)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(width: flagSize, alignment: .center)
    }

    @ViewBuilder
    private static func matchFooter(_ m: MatchPayload, accent: Color, compact: Bool) -> some View {
        switch m.status {
        case .scheduled:
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("\(m.kickoff, style: .relative) · \(m.kickoffClock) · \(m.competition)")
                    .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
        default:
            HStack(spacing: 6) {
                LiveStatusDot(match: m, playingColor: accent)
                liveFooterText(m)
                    .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The footer text for a non-scheduled match. When live, the minute is a
    /// self-ticking clock (`liveClockText`) so it advances between pushes; HT/FT
    /// keep the static label.
    private static func liveFooterText(_ m: MatchPayload) -> Text {
        if let clock = liveClockText(m) {
            return clock + Text(" · \(m.competition)")
        }
        return Text(matchFooterLine(m))
    }

    private static func matchFooterLine(_ m: MatchPayload) -> String {
        switch m.status {
        case .scheduled: return m.competition
        default: return "\(m.statusLine()) · \(m.competition)"
        }
    }

    /// A self-ticking "mm:ss" live clock for a match, or nil when not live. Uses
    /// the `.timer` text style — the only clock ActivityKit re-renders on its own
    /// inside a Live Activity, and it ticks in the home widget too. Each ~1/min
    /// push re-anchors it against the feed's true minute.
    public static func liveClockText(_ m: MatchPayload) -> Text? {
        m.liveClockAnchor.map { Text($0, style: .timer) }
    }

    // MARK: - Game row

    private static func gameRow(_ g: TeamGamePayload, accent: Color, compact: Bool) -> some View {
        let inset = rowInset(compact: compact)
        return HStack(alignment: .center, spacing: 0) {
            abbrSide(g.homeAbbr, score: g.homeScore, showScore: true, compact: compact, align: .center)
                .padding(.leading, inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            scoreCenter(g.scoreText, accent: accent, compact: compact)
                .fixedSize(horizontal: true, vertical: false)
            abbrSide(g.awayAbbr, score: g.awayScore, showScore: true, compact: compact, align: .center)
                .padding(.trailing, inset)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private static func gameFooter(_ g: TeamGamePayload, accent: Color, compact: Bool) -> some View {
        switch g.status {
        case .scheduled:
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("\(g.startTime, style: .relative) · \(g.startClock) · \(g.leagueName)")
                    .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
        default:
            HStack(spacing: 6) {
                LiveStatusDot(game: g, playingColor: accent)
                Text(g.leagueName)
                    .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Side columns

    /// Flag with the FIFA code underneath — centred in a fixed column.
    public static func flagSide(code: String, label: String, compact: Bool) -> some View {
        let flagSize: CGFloat = compact ? 28 : 36
        return VStack(spacing: compact ? 3 : 4) {
            FlagImage(code, size: flagSize, ringed: true)
            teamCodeLabel(code: code, flagSize: flagSize, compact: compact)
        }
        .frame(width: flagSize)
    }

    public static func abbrSide(
        _ abbr: String, score: Int, showScore: Bool, compact: Bool,
        align: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: align, spacing: compact ? 3 : 4) {
            Text(abbr)
                .font(.system(size: compact ? 14 : 16, weight: .heavy, design: .rounded))
            if showScore {
                Text("\(score)")
                    .font(.system(size: compact ? 20 : 24, weight: .heavy, design: .rounded).monospacedDigit())
            }
        }
    }

    // MARK: - Center stats

    /// Kickoff time alone — countdown lives in the footer so the clock never truncates.
    private static func kickoffClock(_ clock: String, accent: Color, compact: Bool) -> some View {
        Text(clock)
            .font(.system(
                size: compact ? 22 : 34,
                weight: .bold,
                design: .rounded
            ).monospacedDigit())
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    public static func kickoffCenter(
        clock: String, kickoff: Date, accent: Color, compact: Bool
    ) -> some View {
        VStack(spacing: compact ? 2 : 3) {
            kickoffClock(clock, accent: accent, compact: compact)
            relativeCountdown(to: kickoff, compact: compact)
        }
    }

    @ViewBuilder
    public static func scoreCenter(_ score: String, accent: Color, compact: Bool) -> some View {
        Text(score)
            .font(.system(
                size: compact ? 22 : 36,
                weight: .bold,
                design: .rounded
            ).monospacedDigit())
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.center)
    }

    /// Relative countdown — wrapped in TimelineView so Live Activities keep ticking.
    private static func relativeCountdown(to date: Date, compact: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Text(date, style: .relative)
                .font((compact ? Font.caption2 : .caption).weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Legacy helpers (in-app list rows)

    public static func flagTeam(code: String, label: String, compact: Bool) -> some View {
        flagSide(code: code, label: label, compact: compact)
    }

    public static func abbrTeam(
        _ abbr: String, score: Int, showScore: Bool, compact: Bool
    ) -> some View {
        abbrSide(abbr, score: score, showScore: showScore, compact: compact)
    }
}
