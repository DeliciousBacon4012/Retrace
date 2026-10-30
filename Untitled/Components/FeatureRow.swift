import SwiftUI

/// One feature in a list: its status, name, and tier.
struct FeatureRow: View {
    let feature: Feature

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feature.isAvailable ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(feature.isAvailable ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            Text(feature.title)
            Spacer(minLength: 8)
            TierBadge(tier: feature.tier)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(feature.isAvailable ? Text("Available") : Text("Planned"))
    }
}

#Preview {
    List(FeatureCatalog.features(in: .capture)) { FeatureRow(feature: $0) }
}
