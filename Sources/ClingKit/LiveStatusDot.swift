import SwiftUI

/// Small status indicator beside a live score — pulses while play is on,
/// solid orange during a break (HT, half), hidden when scheduled/finished.
public struct LiveStatusDot: View {
    public enum Phase: Equatable, Sendable {
        case playing
        case `break`
    }

    public let phase: Phase?
    public var playingColor: Color = .green
    public var breakColor: Color = .orange
    public var size: CGFloat = 6

    public init(phase: Phase?, playingColor: Color = .green) {
        self.phase = phase
        self.playingColor = playingColor
    }

    public init(match: MatchPayload, playingColor: Color = .green, size: CGFloat = 6) {
        self.phase = Self.phase(for: match.status)
        self.playingColor = playingColor
        self.size = size
    }

    public init(game: TeamGamePayload, playingColor: Color = .red, size: CGFloat = 6) {
        self.phase = Self.phase(for: game.status)
        self.playingColor = playingColor
        self.size = size
    }

    public init(fight: FightPayload, playingColor: Color = .red) {
        self.init(phase: fight.status == .live ? .playing : nil, playingColor: playingColor)
    }

    public static func phase(for status: MatchStatus) -> Phase? {
        switch status {
        case .live: .playing
        case .halftime, .suspended: .break
        case .scheduled, .finished: nil
        }
    }

    public static func phase(for status: GameStatus) -> Phase? {
        switch status {
        case .live: .playing
        case .halftime: .break
        case .scheduled, .finished: nil
        }
    }

    public var body: some View {
        switch phase {
        case .playing:
            Image(systemName: "circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(playingColor)
                .symbolEffect(.pulse, options: .repeating)
        case .break:
            Circle()
                .fill(breakColor)
                .frame(width: size, height: size)
        case nil:
            EmptyView()
        }
    }
}
