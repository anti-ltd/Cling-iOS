/**
 The ONE Live Activity configuration. ActivityKit binds a configuration to a
 single `ActivityAttributes` type, so every pin type renders through here:
 the attributes carry `typeID`, and each region view dispatches to the type's
 `PinModule` renderer via `PinRegistry`.

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
            LockScreenPinView(context: context)
        } dynamicIsland: { context in
            let roster = LivePinRoster.onScreen()
            // `DynamicIslandExpandedContentBuilder` has no `buildEither`, so the
            // roster-vs-single choice can't branch the *regions*. Keep the
            // regions fixed and branch inside each region's view content (a
            // normal ViewBuilder): several pins live → the center holds the
            // roster and the other regions stay empty.
            let many = roster.count >= 2
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if !many { RegionView(.expandedLeading, context: context) }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !many { RegionView(.expandedTrailing, context: context) }
                }
                DynamicIslandExpandedRegion(.center) {
                    if many {
                        LivePinListView(pins: roster)
                            .padding(.top, 4)
                    } else {
                        RegionView(.expandedCenter, context: context)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !many { RegionView(.expandedBottom, context: context) }
                }
            } compactLeading: {
                RegionView(.compactLeading, context: context)
            } compactTrailing: {
                RegionView(.compactTrailing, context: context)
            } minimal: {
                RegionView(.minimal, context: context)
            }
            .widgetURL(DeepLink.pin(context.attributes.pinID).url)
            .keylineTint(context.state.appearance.accent.color)
        }
    }
}

// MARK: - Lock screen

private struct LockScreenPinView: View {
    let context: ActivityViewContext<ClingActivityAttributes>

    var body: some View {
        let ctx = context.attributes.renderContext(context.state)
        let accent = ctx.accent
        let roster = LivePinRoster.onScreen()
        return Group {
            if roster.count >= 2 {
                // More than one pin live: the card becomes the roster.
                LivePinListView(pins: roster)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    PinRegistry.module(for: context.attributes.typeID)
                        .lockScreen(ctx)
                    // Honest expiry, on every pin whose life is capped by the
                    // system ceiling rather than its own end. Stale content
                    // also says so — the system dims it, we name it.
                    if context.isStale {
                        expiryLine("No longer pinned — open Cling to renew", tint: .orange)
                    } else if let staleDate = ctx.staleDate, ctx.appearance.showsExpiry, isCeilingBound(ctx) {
                        expiryLine(
                            "Pinned until \(staleDate.formatted(date: .omitted, time: .shortened))",
                            tint: .secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, ctx.density == .compact ? 10 : 14)
        .overlay(borderOverlay(border: ctx.appearance.border, accent: accent))
        .fontDesign(ctx.appearance.fontDesign.design)
        .activityBackgroundTint(backgroundTint(style: ctx.appearance.style, accent: accent))
        .activitySystemActionForegroundColor(accent)
    }

    // The global house style's border, drawn just inside the system's card.
    // The radius approximates the Live Activity container; the DI's compact and
    // expanded regions are system-framed, so their accent edge is `keylineTint`.
    @ViewBuilder private func borderOverlay(border: PinBorder, accent: Color) -> some View {
        if let stroke = border.strokeColor(accent: accent) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(stroke, lineWidth: border.lineWidth)
        }
    }

    /// True when the stale date is the 8h ceiling, not the pin's own end —
    /// a timer ending in 20 minutes needs no "pinned until" caption.
    private func isCeilingBound(_ ctx: PinRenderContext) -> Bool {
        guard let staleDate = ctx.staleDate else { return false }
        if case .timer(let timer) = ctx.payload { return staleDate < timer.endDate }
        return true
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
    /// The system composites this over its own material, so "glass" is a faint
    /// accent wash, "solid" is a confident one, and "outline" stays neutral.
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
    let context: ActivityViewContext<ClingActivityAttributes>

    init(_ region: Region, context: ActivityViewContext<ClingActivityAttributes>) {
        self.region = region
        self.context = context
    }

    var body: some View {
        let module = PinRegistry.module(for: context.attributes.typeID)
        let ctx = context.attributes.renderContext(context.state)
        Group {
            switch region {
            case .expandedLeading:   module.diExpandedLeading(ctx)
            case .expandedTrailing:  module.diExpandedTrailing(ctx)
            case .expandedCenter:    module.diExpandedCenter(ctx)
            case .expandedBottom:    module.diExpandedBottom(ctx) ?? AnyView(EmptyView())
            case .compactLeading:    module.diCompactLeading(ctx)
            case .compactTrailing:   module.diCompactTrailing(ctx)
            case .minimal:           module.diMinimal(ctx)
            }
        }
        .fontDesign(ctx.appearance.fontDesign.design)
    }
}
