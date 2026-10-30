import SwiftUI

/// Every planned feature in one searchable table, filterable by tier.
struct RoadmapView: View {
    @State private var viewModel = RoadmapViewModel()

    var body: some View {
        let rows = viewModel.filteredFeatures

        Table(rows) {
            TableColumn("Feature") { feature in
                FeatureStatusLabel(feature: feature)
            }
            .width(min: 260, ideal: 340)
            TableColumn("Area") { feature in
                Text(feature.area.title)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            TableColumn("Tier") { feature in
                TierBadge(tier: feature.tier)
            }
            .width(min: 60, ideal: 70)
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        }
        .navigationTitle("Roadmap")
        .navigationSubtitle(Text("\(rows.count) features"))
        .searchable(text: $viewModel.searchText, prompt: Text("Search features"))
        .toolbar {
            ToolbarItem {
                Picker("Tier", selection: $viewModel.tierFilter) {
                    Text("All").tag(FeatureTier?.none)
                    ForEach(FeatureTier.allCases) { tier in
                        Text(tier.title).tag(Optional(tier))
                    }
                }
                .pickerStyle(.segmented)
                .help("Filter by tier")
            }
        }
    }
}

/// The feature name with a status icon, used in the Roadmap's first column.
private struct FeatureStatusLabel: View {
    let feature: Feature

    var body: some View {
        Label {
            Text(feature.title)
        } icon: {
            Image(systemName: feature.isAvailable ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(feature.isAvailable ? Color.green : Color.secondary)
        }
        .accessibilityValue(feature.isAvailable ? Text("Available") : Text("Planned"))
    }
}

#Preview {
    NavigationStack {
        RoadmapView()
    }
    .frame(width: 760, height: 500)
}
