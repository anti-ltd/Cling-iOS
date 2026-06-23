/**
 The ONE Live Activity configuration — a roster. The activity's `ContentState`
 carries every live pin (`pins: [PinSnapshot]`, hero first), so this single
 configuration renders the whole board: one pin shows richly (the type's own
 lock-screen card and Dynamic Island regions), several collapse to a stacked
 list with the lead pin driving the compact island.

 Region content is wrapped in real `View` types (not built inline in the
 configuration closures) because `View.body` is `@MainActor` — which makes the
 `@MainActor` registry lookups legal under strict concurrency.
 */
import SwiftUI
import WidgetKit
import ActivityKit

struct ClingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClingActivityAttributes.self) { context in
            RosterLockScreen(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            let pins = context.state.pins
            let hero = pins.first
            // `DynamicIslandExpandedContentBuilder` has no `buildEither`, so the
            // roster-vs-single choice can't branch the *regions*. Keep the
            // regions fixed and branch inside each region's content: several pins
            // live → the center holds the list and the others stay empty.
            let many = pins.count >= 2
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if !many, let hero { RegionView(.expandedLeading, snapshot: hero) }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !many, let hero { RegionView(.expandedTrailing, snapshot: hero) }
                }
                DynamicIslandExpandedRegion(.center) {
                    if many {
                        LivePinListView(pins: pins)
                            .padding(.top, 4)
                    } else if let hero {
                        RegionView(.expandedCenter, snapshot: hero)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !many, let hero { RegionView(.expandedBottom, snapshot: hero) }
                }
            } compactLeading: {
                if let hero { RegionView(.compactLeading, snapshot: hero) }
            } compactTrailing: {
                // One pin: its own trailing glance. Several: how many more there
                // are beyond the lead, so the pill still says "there's a stack".
                if many {
                    Text("+\(pins.count - 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(hero?.appearance.accent.color ?? .secondary)
                } else if let hero {
                    RegionView(.compactTrailing, snapshot: hero)
                }
            } minimal: {
                if let hero { RegionView(.minimal, snapshot: hero) }
            }
            .widgetURL(rosterURL(pins))
            .keylineTint(hero?.appearance.accent.color)
        }
    }

    /// One pin → its detail; several → the app's list (no single pin to favour).
    private func rosterURL(_ pins: [PinSnapshot]) -> URL? {
        guard pins.count == 1, let only = pins.first else {
            return URL(string: "\(ClingKit.urlScheme)://")
        }
        return DeepLink.pin(only.id).url
    }
}

// MARK: - Lock screen

private struct RosterLockScreen: View {
    let state: ClingActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let pins = state.pins
        let hero = pins.first
        let accent = hero?.appearance.accent.color ?? .clear
        return Group {
            if pins.count >= 2 {
                // Several pins live: the card becomes the roster.
                LivePinListView(pins: pins)
            } else if let hero {
                let ctx = hero.renderContext
                VStack(alignment: .leading, spacing: 6) {
                    PinRegistry.module(for: hero.typeID).lockScreen(ctx)
                    // Honest expiry, on every pin whose life is capped by the
                    // system ceiling rather than its own end. Stale content also
                    // says so — the system dims it, we name it.
                    if isStale {
                        expiryLine("No longer pinned — open Cling to renew", tint: .orange)
                    } else if let staleDate = ctx.staleDate, ctx.appearance.showsExpiry, isCeilingBound(ctx) {
                        expiryLine(
                            "Pinned until \(staleDate.formatted(date: .omitted, time: .shortened))",
                            tint: .secondary)
                    }
                }
            } else {
                // No pins in the pushed state (empty roster, or a snapshot that
                // failed to decode). Never collapse to an empty card: a 0-height
                // lock-screen view makes iOS draw its own full-size loading
                // spinner over the whole activity. A quiet branded line instead.
                placeholder
            }
        }
        // Floor the card height too, so a thin render never collapses far enough
        // for the system placeholder to take over.
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, (hero?.appearance.density == .compact) ? 12 : 16)
        .overlay(borderOverlay(border: hero?.appearance.border ?? .none, accent: accent))
        .fontDesign(hero?.appearance.fontDesign.design)
        .activityBackgroundTint(backgroundTint(style: hero?.appearance.style ?? .glass, accent: accent))
        .activitySystemActionForegroundColor(.white)
    }

    // The global house style's border, drawn just inside the system's card.
    @ViewBuilder private func borderOverlay(border: PinBorder, accent: Color) -> some View {
        if let stroke = border.strokeColor(accent: accent) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(stroke, lineWidth: border.lineWidth)
        }
    }

    /// True when the stale date is the 8 h ceiling, not the pin's own end —
    /// a timer ending in 20 minutes needs no "pinned until" caption.
    private func isCeilingBound(_ ctx: PinRenderContext) -> Bool {
        guard let staleDate = ctx.staleDate else { return false }
        if case .timer(let timer) = ctx.payload { return staleDate < timer.endDate }
        return true
    }

    /// Shown only in the degenerate empty-roster case — its sole job is to give
    /// the card non-zero, non-empty content so the system spinner never appears.
    private var placeholder: some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .font(.footnote.weight(.semibold))
            Text("Updating…")
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    private func expiryLine(_ text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(tint)
    }

    /// The pin's surface style, translated to the activity's background tint.
    private func backgroundTint(style: PinStyle, accent: Color) -> Color? {
        switch style {
        case .glass:   accent.opacity(0.18)
        case .solid:   accent.opacity(0.55)
        case .outline: nil
        }
    }
}

// MARK: - Dynamic Island regions

private enum Region {
    case expandedLeading, expandedTrailing, expandedCenter, expandedBottom
    case compactLeading, compactTrailing, minimal
}

private struct RegionView: View {
    let region: Region
    let snapshot: PinSnapshot

    init(_ region: Region, snapshot: PinSnapshot) {
        self.region = region
        self.snapshot = snapshot
    }

    var body: some View {
        let module = PinRegistry.module(for: snapshot.typeID)
        let ctx = snapshot.renderContext
        Group {
            switch region {
            case .expandedLeading:   module.diExpandedLeading(ctx)
            case .expandedTrailing:  module.diExpandedTrailing(ctx)
            case .expandedCenter:    module.diExpandedCenter(ctx)
            case .expandedBottom:    module.diExpandedBottom(ctx) ?? AnyView(EmptyView())
            case .compactLeading:
                module.diCompactLeading(ctx)
                    .frame(maxWidth: .infinity, maxHeight: 28, alignment: .leading)
            case .compactTrailing:
                module.diCompactTrailing(ctx)
                    .frame(maxWidth: .infinity, maxHeight: 28, alignment: .trailing)
            case .minimal:
                module.diMinimal(ctx)
                    .frame(maxWidth: .infinity, maxHeight: 28, alignment: .center)
            }
        }
        .fontDesign(ctx.appearance.fontDesign.design)
    }
}
