/**
 The pin's badge: its symbol on an accent-tinted rounded square. The shared
 visual anchor across list rows, lock-screen cards, and the expanded island.
 Pure view — widget-safe.
 */
import SwiftUI
import iUXiOS

public struct PinGlyph: View {
    let symbolName: String
    let fill: AnyShapeStyle
    let size: CGFloat

    public init(symbolName: String, accent: Color, size: CGFloat = 36) {
        self.symbolName = symbolName
        self.fill = AnyShapeStyle(accent)
        self.size = size
    }

    /// The full appearance treatment — gradient accents render as gradients.
    public init(appearance: PinAppearance, size: CGFloat = 36) {
        self.symbolName = appearance.symbolName
        self.fill = AnyShapeStyle(appearance.accentGradient)
        self.size = size
    }

    public var body: some View {
        let rr = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                rr.fill(fill)
                    .overlay(
                        rr.fill(
                            LinearGradient(
                                colors: [.white.opacity(UX.Glass.sheenTopOpacity), .clear],
                                startPoint: .top, endPoint: .bottom)
                        )
                    )
                    .overlay(
                        rr.strokeBorder(.white.opacity(UX.Glass.rimTopOpacity * 0.6),
                                        lineWidth: UX.Glass.rimWidth)
                    )
            }
    }
}
