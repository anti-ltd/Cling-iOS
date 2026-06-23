import SwiftUI

/// Sports matchup row: equal flanking columns with a fixed-width hero stat in
/// the middle — each team sits centered in its half instead of hugging the edges.
struct MatchupHeroRow<Leading: View, Center: View, Trailing: View>: View {
    var spacing: CGFloat = 10
    /// Minimum width reserved for the center stat so kickoff/score never gets
    /// squeezed by long team names.
    var centerMinWidth: CGFloat = 80
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var center: () -> Center
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            leading()
                .frame(maxWidth: .infinity, alignment: .center)
            center()
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: centerMinWidth)
                .layoutPriority(1)
            trailing()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
