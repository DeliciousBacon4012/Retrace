import SwiftUI

/// The main window: the selected tab's page, with a floating glass tab bar at the bottom.
struct MainView: View {
    @State private var viewModel = MainViewModel()

    var body: some View {
        page
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GlassTabBar(selection: $viewModel.selectedTab)
                    .padding(.bottom, 16)
                    .padding(.top, 8)
            }
            .navigationTitle(viewModel.selectedTab.title)
            .frame(minWidth: 640, minHeight: 460)
    }

    @ViewBuilder
    private var page: some View {
        switch viewModel.selectedTab {
        case .home:
            HomeView()
        case .capture, .record, .library:
            FeatureListView(areas: viewModel.selectedTab.areas)
                .id(viewModel.selectedTab)
        case .roadmap:
            RoadmapView()
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    MainView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 900, height: 600)
}
