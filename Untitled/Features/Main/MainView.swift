import SwiftUI

/// The main window: a sidebar of areas and a detail pane.
struct MainView: View {
    @State private var viewModel = MainViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $viewModel.selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 680, minHeight: 440)
    }

    @ViewBuilder
    private var detail: some View {
        switch viewModel.selection {
        case .home, nil:
            HomeView()
        case .area(let area):
            FeatureAreaView(area: area)
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
}
