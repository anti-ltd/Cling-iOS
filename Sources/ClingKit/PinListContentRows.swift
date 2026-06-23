/**
 Non-sports list-row layouts for the pin list — note, timer, and ticker.
 Sports pins use `PinListSportsRow`.
 */
import SwiftUI
import iUXiOS

// MARK: - Note

struct NoteListRow: View {
    let payload: PinPayload
    let appearance: PinAppearance
    @Environment(\.pinListStyle) private var style

    private var note: NotePayload? {
        if case .note(let n) = payload { return n }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note?.text ?? "")
                    .font(style == .featured ? .title3 : .body)
                    .lineLimit(style == .featured ? 4 : 2)
                if let host = note?.sourceURL?.host() {
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let filename = note?.photoFilename {
                noteThumb(filename: filename)
            }
        }
    }

    @ViewBuilder private func noteThumb(filename: String) -> some View {
        let size: CGFloat = style == .featured ? 56 : 44
        #if canImport(UIKit)
        GlassThumb(
            image: PhotoStore.shared.loadImage(filename).map(Image.init(uiImage:)),
            size: CGSize(width: size, height: size),
            placeholderSymbol: "photo")
        #else
        GlassThumb(image: nil, size: CGSize(width: size, height: size), placeholderSymbol: "photo")
        #endif
    }
}

// MARK: - Timer

struct TimerListRow: View {
    let timer: TimerPayload?
    let appearance: PinAppearance
    @Environment(\.pinListStyle) private var style

    private var featured: Bool { style == .featured }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timer?.label.isEmpty == false ? timer!.label : "Timer")
                    .font(featured ? .title3.weight(.medium) : .body)
                if let timer, timer.endDate <= .now {
                    Text("Done")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let timer, timer.endDate > .now {
                CountdownText(from: timer.startDate, until: timer.endDate)
                    .font(.system(
                        size: featured ? 36 : 24,
                        weight: .bold,
                        design: .rounded
                    ).monospacedDigit())
                    .foregroundStyle(appearance.accent.color)
            }
        }
    }
}

// MARK: - Ticker

struct TickerListRow: View {
    let ticker: TickerPayload
    let appearance: PinAppearance
    @Environment(\.pinListStyle) private var style

    private var featured: Bool { style == .featured }

    private var moveColor: Color {
        ticker.isUp ? Color(red: 0.20, green: 0.80, blue: 0.35)
                      : Color(red: 0.95, green: 0.30, blue: 0.28)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ticker.titleLine)
                    .font(featured ? .title3.weight(.medium) : .body.weight(.medium))
                    .lineLimit(1)
                if ticker.price > 0 {
                    Text(ticker.changePercentText)
                        .font(featured ? .subheadline : .caption)
                        .monospacedDigit()
                        .foregroundStyle(moveColor)
                } else {
                    Text("Fetching quote…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if ticker.price > 0 {
                Text(ticker.priceText)
                    .font(.system(
                        size: featured ? 32 : 22,
                        weight: .bold,
                        design: .rounded
                    ).monospacedDigit())
                    .foregroundStyle(appearance.accent.color)
            }
        }
    }
}
