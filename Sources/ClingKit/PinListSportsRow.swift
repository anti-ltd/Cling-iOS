/**
 Hero-style list rows for live-sports pins — the same matchup layout as the
 lock-screen card, scaled for the pin list (compact vs featured).
 */
import SwiftUI
import iUXiOS

// MARK: - Match

public struct PinListMatchRow: View {
    public let match: MatchPayload
    public let accent: Color
    @Environment(\.pinListStyle) private var style

    public init(match: MatchPayload, accent: Color) {
        self.match = match
        self.accent = accent
    }

    private var featured: Bool { style == .featured }

    public var body: some View {
        VStack(alignment: .leading, spacing: featured ? 12 : 8) {
            MatchupHeroRow(spacing: featured ? 14 : 10) {
                teamColumn(code: match.homeCode)
            } center: {
                centerStat
            } trailing: {
                teamColumn(code: match.awayCode)
            }

            HStack(spacing: 6) {
                LiveStatusDot(match: match, playingColor: accent)
                Text("\(match.statusLine()) · \(match.competition)")
                    .font(featured ? .subheadline.weight(.medium) : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if featured, let event = match.lastEvent, !event.isEmpty {
                commentaryLine(event)
            }
        }
    }

    @ViewBuilder private var centerStat: some View {
        SportsLockScreen.scoreCenter(match.scoreText, accent: accent, compact: !featured)
    }

    private func teamColumn(code: String) -> some View {
        SportsLockScreen.flagTeam(code: code, label: code, compact: !featured)
    }

    private func commentaryLine(_ event: String) -> some View {
        Text(event)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent)
                    .frame(width: 3)
            }
    }
}

// MARK: - Game

public struct PinListGameRow: View {
    public let game: TeamGamePayload
    public let accent: Color
    @Environment(\.pinListStyle) private var style

    public init(game: TeamGamePayload, accent: Color) {
        self.game = game
        self.accent = accent
    }

    private var featured: Bool { style == .featured }

    public var body: some View {
        VStack(alignment: .leading, spacing: featured ? 12 : 8) {
            MatchupHeroRow(spacing: featured ? 14 : 10) {
                teamColumn(game.homeAbbr, score: game.homeScore, showScore: true)
            } center: {
                centerStat
            } trailing: {
                teamColumn(game.awayAbbr, score: game.awayScore, showScore: true)
            }

            HStack(spacing: 6) {
                LiveStatusDot(game: game, playingColor: accent)
                Text("\(game.leagueName) · \(game.statusLine())")
                    .font(featured ? .subheadline.weight(.medium) : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var centerStat: some View {
        if game.status == .live || game.status == .halftime {
            Text(game.statusLine())
                .font(.system(
                    size: featured ? 28 : 22,
                    weight: .bold,
                    design: .rounded
                ).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)
        } else {
            SportsLockScreen.scoreCenter(game.scoreText, accent: accent, compact: !featured)
        }
    }

    private func teamColumn(_ abbr: String, score: Int, showScore: Bool) -> some View {
        SportsLockScreen.abbrTeam(abbr, score: score, showScore: showScore, compact: !featured)
    }
}

// MARK: - Fight

public struct PinListFightRow: View {
    public let fight: FightPayload
    public let accent: Color
    @Environment(\.pinListStyle) private var style

    public init(fight: FightPayload, accent: Color) {
        self.fight = fight
        self.accent = accent
    }

    private var featured: Bool { style == .featured }

    public var body: some View {
        VStack(alignment: .leading, spacing: featured ? 12 : 8) {
            MatchupHeroRow(spacing: featured ? 14 : 10) {
                fighterColumn(fight.redLast, tint: .red)
            } center: {
                centerStat
            } trailing: {
                fighterColumn(fight.blueLast, tint: .blue)
            }

            HStack(spacing: 6) {
                LiveStatusDot(fight: fight, playingColor: accent)
                Text(fight.boutName.isEmpty
                     ? fight.statusLine()
                     : "\(fight.statusLine()) · \(fight.boutName)")
                    .font(featured ? .subheadline.weight(.medium) : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var centerStat: some View {
        if let rc = fight.roundClock {
            Text(rc)
                .font(.system(
                    size: featured ? 34 : 24,
                    weight: .bold,
                    design: .rounded
                ).monospacedDigit())
                .foregroundStyle(accent)
        } else if fight.status == .finished {
            Text(fight.method ?? "def.")
                .font(.system(size: featured ? 28 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        } else if fight.status == .upcoming {
            VStack(spacing: 2) {
                Text(startClock)
                    .font(.system(
                        size: featured ? 34 : 24,
                        weight: .bold,
                        design: .rounded
                    ).monospacedDigit())
                    .foregroundStyle(accent)
                Text(fight.startDate, style: .relative)
                    .font((featured ? Font.subheadline : .caption).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        } else {
            Text("vs")
                .font(.system(size: featured ? 28 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
        }
    }

    private var startClock: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: fight.startDate)
    }

    private func fighterColumn(_ name: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: featured ? 36 : 28, height: featured ? 36 : 28)
                .overlay {
                    Text(String(name.prefix(1)))
                        .font(.system(size: featured ? 15 : 12, weight: .bold))
                        .foregroundStyle(tint)
                }
            Text(name)
                .font((featured ? Font.caption : .caption2).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
