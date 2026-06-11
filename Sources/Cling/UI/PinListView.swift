/**
 The pin list: each pin's own module renders its row; the list supplies the
 glass tile, status chrome, navigation, and removal.
 */
import SwiftUI
import iUXiOS

struct PinListView: View {
    @Environment(AppModel.self) private var model
    let onAdd: () -> Void

    var body: some View {
        let pins = model.activePins
        ScrollView {
            LazyVStack(spacing: UX.cardSpacing) {
                if !model.activitiesEnabled {
                    // The product can't do its job without Live Activities —
                    // say so at the top, not in a buried setting.
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
                    ForEach(pins) { pin in
                        PinRow(pin: pin)
                    }
                }
            }
            .padding(.horizontal, UX.screenPadding)
            .padding(.vertical, UX.cardSpacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(UX.Motion.morph, value: pins.map(\.id))
    }

    /// A one-line read on the board: how many are pinned, and whether any need
    /// attention. Small, secondary — the cards are the content.
    @ViewBuilder private func summary(for pins: [Pin]) -> some View {
        let expired = pins.filter { $0.status == .stale }.count
        HStack(spacing: 6) {
            Text("\(pins.count) pinned")
                .foregroundStyle(.secondary)
            if expired > 0 {
                Text("·").foregroundStyle(.tertiary)
                Label(expired == 1 ? "1 needs renewing" : "\(expired) need renewing",
                      systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

private struct PinRow: View {
    @Environment(AppModel.self) private var model
    let pin: Pin

    /// Expired pins should grab you — they're warm and want renewing. Live and
    /// pending pins wear their own accent, calm.
    private var tileTint: Color {
        pin.status == .stale ? .orange : pin.appearance.accent.color
    }

    var body: some View {
        NavigationLink(value: pin.id) {
            VStack(alignment: .leading, spacing: 10) {
                PinRegistry.module(for: pin.typeID).listRow(pin)
                    .fontDesign(pin.appearance.fontDesign.design)
                HStack(spacing: 6) {
                    statusChip
                    Spacer(minLength: 0)
                    if pin.status == .live, let staleDate = pin.staleDate, pin.isRenewable {
                        ExpiryBadge(date: staleDate)
                    } else {
                        Text(pin.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous))
            .glassTile(tint: tileTint)
            // A leading accent rib — the "pinned tab" tell. As an overlay it
            // resolves to the card's full height automatically.
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(pin.status == .stale
                          ? AnyShapeStyle(Color.orange)
                          : AnyShapeStyle(pin.appearance.accentGradient))
                    .frame(width: 4)
                    .padding(.vertical, 14)
                    .padding(.leading, 7)
            }
        }
        .buttonStyle(.glassBloom)
        .contextMenu {
            Button(role: .destructive) {
                model.delete(pin)
            } label: {
                Label("Remove pin", systemImage: "pin.slash")
            }
        }
    }

    /// Honest status: pending pins say so (they're not in the island yet),
    /// stale pins say so. The expiry badge itself arrives with the lifetime
    /// phase, when pins have real stale dates.
    @ViewBuilder private var statusChip: some View {
        switch pin.status {
        case .pending:
            label("Not pinned yet", symbol: "pin.slash", tint: .secondary)
        case .live:
            label("Pinned", symbol: "pin.fill", tint: pin.appearance.accent.color)
        case .stale:
            label("Expired — tap to renew", symbol: "clock.badge.exclamationmark", tint: .orange)
        case .ended:
            label("Ended", symbol: "checkmark", tint: .secondary)
        }
    }

    private func label(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(tint)
    }
}
