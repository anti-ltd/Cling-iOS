/**
 The Ticker pin: a tracked market quote in the Dynamic Island. Symbol, live
 price, the day's change (absolute + percent) and a small intraday sparkline —
 kept current by a quote API, refreshed via server-pushed Live Activity updates
 (see `ActivityPushContract`), so a move lands in the island with Cling closed.

 Same plugin shape as the sport pins. The change colour follows the finance convention
 (green up / red down) rather than the pin's accent — a red day should read red
 no matter what colour the user picked for the glyph.
 */
import SwiftUI
import iUXiOS

@MainActor
public enum TickerPinModule: PinModule {
    public static let typeID: PinTypeID = .ticker
    public static let displayName = "Ticker"
    public static let systemImage = "chart.line.uptrend.xyaxis"
    public static let symbolChoices = [
        "chart.line.uptrend.xyaxis", "chart.bar.fill", "dollarsign.circle.fill",
        "bitcoinsign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill",
        "arrow.up.right.circle.fill", "building.columns.fill",
    ]

    private static func ticker(_ payload: PinPayload) -> TickerPayload? {
        if case .ticker(let t) = payload { return t }
        return nil
    }

    /// Finance-convention colour for the day's move — green up, red down.
    private static func moveColor(_ t: TickerPayload) -> Color {
        t.isUp ? Color(red: 0.20, green: 0.80, blue: 0.35)
               : Color(red: 0.95, green: 0.30, blue: 0.28)
    }

    // MARK: App-side

    public static func quickAddForm(draft: Binding<PinDraft>) -> AnyView {
        AnyView(TickerQuickAddForm(draft: draft))
    }

    public static func listRow(_ pin: Pin) -> AnyView {
        guard let t = ticker(pin.payload) else { return AnyView(EmptyView()) }
        return AnyView(TickerListRow(ticker: t, appearance: pin.appearance))
    }

    // MARK: Live Activity

    public static func lockScreen(_ ctx: PinRenderContext) -> AnyView {
        guard let t = ticker(ctx.payload) else { return AnyView(EmptyView()) }
        let compact = ctx.density == .compact
        let move = moveColor(t)
        return AnyView(
            VStack(spacing: compact ? 5 : 8) {
                HStack(spacing: 6) {
                    Text(t.symbol).font(.caption.weight(.bold))
                    if !t.name.isEmpty {
                        Text(t.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let tag = t.stateTag {
                        Text(tag).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(t.priceText)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    changeBadge(t, move: move)
                }
                if !t.spark.isEmpty {
                    Sparkline(points: t.spark, color: move)
                        .frame(height: compact ? 22 : 30)
                }
            }
        )
    }

    public static func diExpandedLeading(_ ctx: PinRenderContext) -> AnyView {
        guard let t = ticker(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 1) {
                Text(t.symbol).font(.headline.weight(.semibold)).lineLimit(1)
                if let tag = t.stateTag {
                    Text(tag).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4).padding(.top, 2)
        )
    }

    public static func diExpandedTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let t = ticker(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .trailing, spacing: 1) {
                Text(t.priceText)
                    .font(.headline.weight(.semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(t.changePercentText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(moveColor(t))
                    .lineLimit(1)
            }
            .padding(.trailing, 4).padding(.top, 2)
        )
    }

    public static func diExpandedCenter(_ ctx: PinRenderContext) -> AnyView {
        guard let t = ticker(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            Image(systemName: t.arrow)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(moveColor(t))
        )
    }

    public static func diExpandedBottom(_ ctx: PinRenderContext) -> AnyView? {
        guard let t = ticker(ctx.payload), !t.spark.isEmpty else { return nil }
        return AnyView(
            Sparkline(points: t.spark, color: moveColor(t)).frame(height: 24)
        )
    }

    public static func diCompactLeading(_ ctx: PinRenderContext) -> AnyView {
        guard let t = ticker(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            Text(t.symbol).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 52)
        )
    }

    public static func diCompactTrailing(_ ctx: PinRenderContext) -> AnyView {
        guard let t = ticker(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            Text(t.compactChange)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(moveColor(t))
                .lineLimit(1)
        )
    }

    public static func diMinimal(_ ctx: PinRenderContext) -> AnyView {
        guard let t = ticker(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            Image(systemName: t.arrow)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(moveColor(t))
        )
    }

    public static func liveRow(_ ctx: PinRenderContext) -> AnyView {
        guard let t = ticker(ctx.payload) else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 8) {
                Text(t.symbol).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(t.priceText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(t.changePercentText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(moveColor(t))
                    .lineLimit(1)
            }
        )
    }

    // MARK: Bits

    /// "▲ +1.62 (+0.71%)" in the move colour — the lock-screen change chip.
    private static func changeBadge(_ t: TickerPayload, move: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: t.arrow).font(.system(size: 9, weight: .bold))
            Text("\(t.changeText) (\(t.changePercentText))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(move)
    }
}

/// A minimal intraday line — the price path normalised to its own min/max, drawn
/// in the move colour with a soft fade underneath. Pure view, widget-safe; no
/// axes, no labels (the numbers live above it).
private struct Sparkline: View {
    let points: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = normalized(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    // Soft fill under the line.
                    path(pts, close: true, in: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.25), color.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom))
                    path(pts, close: false, in: geo.size)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    /// Map the values into the box, y-flipped (higher price → higher on screen),
    /// with a hair of vertical padding so the extremes aren't clipped.
    private func normalized(in size: CGSize) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let lo = points.min() ?? 0
        let hi = points.max() ?? 1
        let span = hi - lo
        let padY = size.height * 0.1
        let usableH = size.height - padY * 2
        let stepX = size.width / CGFloat(points.count - 1)
        return points.enumerated().map { i, v in
            let frac = span > 0 ? (v - lo) / span : 0.5
            let y = padY + usableH * (1 - CGFloat(frac))
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }
    }

    private func path(_ pts: [CGPoint], close: Bool, in size: CGSize) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        if close, let last = pts.last {
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.addLine(to: CGPoint(x: first.x, y: size.height))
            p.closeSubpath()
        }
        return p
    }
}

/// Enter a symbol and pick stock or crypto — the quote API fills in the name,
/// price, change and sparkline from there.
private struct TickerQuickAddForm: View {
    @Binding var draft: PinDraft
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(placeholder, text: $draft.tickerSymbol)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Capsule().fill(.ultraThinMaterial))
                .focused($focused)
                .onAppear { focused = true }

            Picker("Market", selection: $draft.tickerMarket) {
                ForEach(TickerMarket.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Text("The name, price, day change and sparkline fill in once the quote is found.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var placeholder: String {
        draft.tickerMarket == .crypto ? "Symbol (e.g. BTC)" : "Symbol (e.g. AAPL)"
    }
}
