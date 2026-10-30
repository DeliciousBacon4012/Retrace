import SwiftUI

/// A page listing the planned features of one or more areas, grouped by area.
struct FeatureListView: View {
    let areas: [FeatureArea]

    var body: some View {
        List {
            ForEach(areas) { area in
                Section {
                    ForEach(sorted(FeatureCatalog.features(in: area))) { FeatureRow(feature: $0) }
                } header: {
                    AreaHeader(area: area)
                }
            }
        }
        .listStyle(.inset)
    }

    /// Core first, then Next, then Maybe, keeping catalog order within each tier.
    private func sorted(_ features: [Feature]) -> [Feature] {
        FeatureTier.allCases.flatMap { tier in features.filter { $0.tier == tier } }
    }
}

private struct AreaHeader: View {
    let area: FeatureArea

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: area.symbolName)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(area.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(area.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .textCase(nil)
    }
}

#Preview {
    FeatureListView(areas: AppTab.capture.areas)
        .frame(width: 640, height: 600)
}
