/**
 The pin list: each pin's own module renders its row; the list supplies the
 glass tile, status chrome, navigation, and removal.
 */
import SwiftUI
import UIKit
import iUXiOS

struct PinListView: View {
    @Environment(AppModel.self) private var model
    let onAdd: () -> Void
    let onOpen: (UUID) -> Void

    var body: some View {
        let pins = model.activePins
        ScrollView {
            LazyVStack(spacing: UX.cardSpacing + 4) {
                if !model.activitiesEnabled {
                    activitiesWarning
                }
                if pins.isEmpty {
                    EmptyStateCard(
                        symbol: "pin",
                        title: "Nothing pinned",
                        message: "Anything you pin stays in your Dynamic Island and on your lock screen until you let go.",
                        actionLabel: "Pin something",
                        action: onAdd
                    )
                    .padding(.top, 40)
                } else {
                    summary(for: pins)
                    ForEach(Array(pins.enumerated()), id: \.element.id) { index, pin in
                        PinRow(
                            pin: pin,
                            isFeatured: shouldFeature(pin, at: index, in: pins),
                            onOpen: onOpen
                        )
                    }
                }
            }
            .padding(.horizontal, UX.screenPadding)
            .padding(.vertical, UX.cardSpacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(UX.Motion.morph, value: pins.map(\.id))
        .task { Haptics.warm() }
    }

    // MARK: - Summary

    @ViewBuilder private func summary(for pins: [Pin]) -> some View {
        let liveNow = pins.filter { PinListMetrics.isLiveNow($0) }.count
        let stale = pins.filter { $0.status == .stale }.count
        let pending = pins.filter { $0.status == .pending }.count

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SummaryChip(
                    label: pins.count == 1 ? "1 pin" : "\(pins.count) pins",
                    symbol: "pin.fill",
                    tint: model.chromeAccent
                )
                if liveNow > 0 {
                    SummaryChip(
                        label: liveNow == 1 ? "Live now" : "\(liveNow) live",
                        symbol: "dot.radiowaves.left.and.right",
                        tint: .green
                    )
                }
                if pending > 0 {
                    SummaryChip(
                        label: pending == 1 ? "1 waiting" : "\(pending) waiting",
                        symbol: "clock.arrow.circlepath",
                        tint: .secondary
                    )
                }
                if stale > 0 {
                    SummaryChip(
                        label: stale == 1 ? "1 expired" : "\(stale) expired",
                        symbol: "clock.badge.exclamationmark",
                        tint: .orange
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.bottom, 4)
    }

    private var activitiesWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Live Activities are off for Cling. Pins can't reach the Dynamic Island until you enable them in Settings → Cling.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(tint: .orange)
    }

    private func shouldFeature(_ pin: Pin, at index: Int, in pins: [Pin]) -> Bool {
        if pins.count == 1 { return true }
        if index == 0, PinListMetrics.isLiveNow(pin) { return true }
        return false
    }
}

// MARK: - Summary chip

private struct SummaryChip: View {
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassPill(tint: tint.opacity(0.35))
    }
}

// MARK: - Pin row

private struct PinRow: View {
    @Environment(AppModel.self) private var model
    let pin: Pin
    let isFeatured: Bool
    let onOpen: (UUID) -> Void

    private var tileTint: Color {
        pin.status == .stale ? .orange : pin.appearance.accent.color
    }

    private var liveNow: Bool { PinListMetrics.isLiveNow(pin) && pin.status == .live }

    var body: some View {
        SwipeToRemove(onDelete: { model.delete(pin) }) {
            rowLink
        }
        .contextMenu {
            Button(role: .destructive) {
                model.delete(pin)
            } label: {
                Label("Remove pin", systemImage: "pin.slash")
            }
        }
    }

    private var rowLink: some View {
        VStack(alignment: .leading, spacing: isFeatured ? 14 : 10) {
            cardHeader
            PinRegistry.module(for: pin.typeID).listRow(pin)
                .fontDesign(pin.appearance.fontDesign.design)
                .environment(\.pinListStyle, isFeatured ? .featured : .compact)
            if showsFooter {
                cardFooter
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, isFeatured ? 18 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous))
        .glassTile(tint: tileTint, shadow: isFeatured)
        .overlay { liveGlow }
        .contentShape(RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous))
        .onTapGesture { onOpen(pin.id) }
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            PinGlyph(appearance: pin.appearance, size: isFeatured ? 28 : 22)
            Text(PinRegistry.module(for: pin.typeID).displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            headerTrailing
        }
    }

    @ViewBuilder private var headerTrailing: some View {
        switch pin.status {
        case .pending:
            StatusPill(text: "Waiting", symbol: "clock.arrow.circlepath", tint: .secondary)
        case .stale:
            StatusPill(text: "Expired", symbol: "clock.badge.exclamationmark", tint: .orange)
        case .live:
            if liveNow {
                StatusPill(text: "Live", symbol: "dot.radiowaves.left.and.right", tint: .green)
            } else if let staleDate = pin.staleDate, pin.isRenewable {
                ExpiryBadge(date: staleDate)
            }
        case .ended:
            StatusPill(text: "Ended", symbol: "checkmark", tint: .secondary)
        }
    }

    private var showsFooter: Bool {
        pin.status == .pending || pin.status == .stale
    }

    @ViewBuilder private var cardFooter: some View {
        switch pin.status {
        case .pending:
            Text("Tap to finish pinning to your Dynamic Island")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .stale:
            Text("Tap to renew — your pin fell off the island")
                .font(.caption)
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var liveGlow: some View {
        if liveNow {
            RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous)
                .strokeBorder(tileTint.opacity(0.45), lineWidth: 1)
                .shadow(color: tileTint.opacity(0.28), radius: isFeatured ? 16 : 10)
        }
    }
}

private struct StatusPill: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassPill(tint: tint.opacity(0.25))
    }
}

// MARK: - Live detection

private enum PinListMetrics {
    static func isLiveNow(_ pin: Pin) -> Bool {
        switch pin.payload {
        case .match(let m):  return m.isLive
        case .game(let g):   return g.status == .live || g.status == .halftime
        case .fight(let f):  return f.status == .live
        case .timer(let t):  return t.endDate > .now
        default:             return false
        }
    }
}

// MARK: - Swipe to remove

private struct SwipeToRemove<Content: View>: View {
    var onDelete: () -> Void
    @ViewBuilder var content: Content

    private let commit: CGFloat = 200
    private let reveal: CGFloat = 92

    @State private var offset: CGFloat = 0
    @State private var armedHaptic = false

    private var armed: Bool { -offset >= commit }

    var body: some View {
        content
            .offset(x: offset)
            .background(removeZone)
            .simultaneousGesture(swipe)
    }

    private var removeZone: some View {
        RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous)
            .fill(Color.red.opacity(0.18 + 0.55 * min(1, -offset / commit)))
            .overlay(alignment: .trailing) {
                VStack(spacing: 4) {
                    Image(systemName: armed ? "pin.slash.fill" : "pin.slash")
                        .font(.system(size: 18, weight: .semibold))
                    Text(armed ? "Release" : "Remove")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.trailing, 24)
                .opacity(Double(min(1, -offset / reveal)))
            }
            .opacity(offset < 0 ? 1 : 0)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                Haptics.prepareArm()
                let dx = min(0, value.translation.width)
                offset = dx < -commit ? -(commit + (-dx - commit) * 0.32) : dx
                if armed && !armedHaptic {
                    Haptics.arm()
                    armedHaptic = true
                } else if !armed {
                    armedHaptic = false
                }
            }
            .onEnded { _ in
                if armed {
                    onDelete()
                } else {
                    withAnimation(UX.Motion.morph) { offset = 0 }
                    armedHaptic = false
                }
            }
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    private static let armGen = UIImpactFeedbackGenerator(style: .rigid)
    private static let commitGen = UIImpactFeedbackGenerator(style: .medium)
    private static let notifyGen = UINotificationFeedbackGenerator()

    static func warm() {
        armGen.prepare()
        commitGen.prepare()
        notifyGen.prepare()
    }

    static func prepareArm() { armGen.prepare() }

    static func arm() {
        armGen.impactOccurred()
        armGen.prepare()
    }

    static func commit() {
        commitGen.impactOccurred()
        commitGen.prepare()
    }

    static func success() {
        notifyGen.notificationOccurred(.success)
        notifyGen.prepare()
    }
}
