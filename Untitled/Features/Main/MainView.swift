import SwiftUI

/// The main window. Navigation and actions use system containers (a tab view and
/// the window toolbar) so macOS draws them in Liquid Glass, with its own physics,
/// accent color, and accessibility settings.
struct MainView: View {
    @Environment(AppDependencies.self) private var dependencies
    @SceneStorage("selectedTab") private var selection: AppTab = .capture

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.capture.title, systemImage: AppTab.capture.symbolName, value: AppTab.capture) {
                CaptureHomeView(showLibrary: { selection = .library })
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.symbolName, value: AppTab.library) {
                LibraryView()
            }
        }
        .tabViewStyle(.tabBarOnly)
        .focusedSceneValue(\.selectedTab, $selection)
        .toolbar {
            CaptureToolbar(capture: dependencies.capture)
        }
        .frame(minWidth: 680, minHeight: 480)
    }
}

extension FocusedValues {
    /// The main window's tab, so View menu commands can switch it.
    @Entry var selectedTab: Binding<AppTab>?
}

/// Capture buttons in the window toolbar. macOS groups them on one glass capsule.
private struct CaptureToolbar: ToolbarContent {
    let capture: CaptureCoordinator

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ForEach(QuickAction.screenshots) { action in
                Button(action.title, systemImage: action.symbolName) {
                    if let mode = action.captureMode {
                        Task { await capture.capture(mode) }
                    }
                }
                .help(action.title)
                .disabled(capture.isCapturing)
            }
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    MainView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 900, height: 600)
}
