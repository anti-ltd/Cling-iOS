/**
 The signature surface: a pin shown the way it actually lives — floating on a
 phone's lock screen. A darkened, accent-washed "screen" plate with the time
 and date peeking at the top, and the pin's *real* lock-screen renderer (the
 same code the widget runs) resting on its activity surface below.

 This is what makes Cling look like what it does. It's the hero of the detail
 screen and the live preview in the appearance editor — what you see here is
 literally what your lock screen shows.
 */
import SwiftUI
import iUXiOS

struct LockScreenStage: View {
    let typeID: PinTypeID
    let payload: PinPayload
    let appearance: PinAppearance
    /// When the pin goes stale — drives the "pinned until" caption when the
    /// pin opts into showing it. Nil in default-appearance previews.
    var staleDate: Date? = nil

    private var context: PinRenderContext {
        PinRenderContext(pinID: UUID(), payload: payload, appearance: appearance, staleDate: staleDate)
    }

    var body: some View {
        let module = PinRegistry.module(for: typeID)
        VStack(spacing: 18) {
            clock
            module.lockScreen(context)
                .padding(.horizontal, 16)
                .padding(.vertical, appearance.density == .compact ? 12 : 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(activitySurface)
                .padding(.horizontal, 14)
        }
        .padding(.top, 22)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
        .fontDesign(appearance.fontDesign.design)
        .background(screen)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        .animation(UX.Motion.morph, value: appearance)
    }

    // The faux lock-screen wallpaper: deep black with a soft pool of the pin's
    // accent up top, so the plate dresses itself in the pin's colour.
    private var screen: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [appearance.accent.color.opacity(0.30),
                         (appearance.accentEnd ?? appearance.accent).color.opacity(0.10),
                         .black],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [appearance.accent.color.opacity(0.22), .clear],
                center: .top, startRadius: 0, endRadius: 260)
        }
    }

    // The peeking clock — a lock screen tell, kept quiet so the pin stays the
    // subject. Live, because a frozen clock looks broken.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(spacing: 2) {
                Text(ctx.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
    }

    // Approximates the tint the lock screen washes under a Live Activity, per
    // the pin's chosen surface style — mirrors the widget's own treatment.
    @ViewBuilder private var activitySurface: some View {
        let rr = RoundedRectangle(cornerRadius: UX.Glass.tileRadius, style: .continuous)
        switch appearance.style {
        case .glass:
            rr.fill(.ultraThinMaterial)
                .overlay(rr.fill(appearance.accent.color.opacity(0.18)))
                .overlay(rr.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        case .solid:
            rr.fill(.ultraThinMaterial)
                .overlay(rr.fill(appearance.accent.color.opacity(0.55)))
        case .outline:
            rr.fill(.black.opacity(0.25))
                .overlay(rr.strokeBorder(appearance.accent.color.opacity(0.6), lineWidth: 1))
        }
    }
}
