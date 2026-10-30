import SwiftUI

/// A small capsule showing when a feature is planned.
struct TierBadge: View {
    let tier: FeatureTier

    var body: some View {
        Text(tier.title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
            .accessibilityLabel(Text("Planned: \(tier.title)"))
    }

    private var tint: Color {
        switch tier {
        case .core: .accentColor
        case .next: .orange
        case .maybe: .secondary
        }
    }
}

#Preview {
    HStack {
        ForEach(FeatureTier.allCases) { TierBadge(tier: $0) }
    }
    .padding()
}
