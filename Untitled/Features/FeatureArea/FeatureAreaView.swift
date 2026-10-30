import SwiftUI

/// A page for one area of the app, listing what it will do, grouped by tier.
struct FeatureAreaView: View {
    let area: FeatureArea

    private var features: [Feature] { FeatureCatalog.features(in: area) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: area.symbolName)
                        .font(.system(size: 32))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(area.title)
                        .font(.title2.weight(.semibold))
                    Text(area.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }

            ForEach(FeatureTier.allCases) { tier in
                let items = features.filter { $0.tier == tier }
                if !items.isEmpty {
                    Section(tier.title) {
                        ForEach(items) { FeatureRow(feature: $0) }
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle(area.title)
    }
}

#Preview {
    FeatureAreaView(area: .replayBuffer)
        .frame(width: 600, height: 500)
}
