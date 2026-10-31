import SwiftUI

/// The main window: a dashboard with the capture home, the library, and every setting in
/// one sidebar, the way a menu bar app's window usually works. The system sidebar and
/// toolbar draw in Liquid Glass on their own.
struct MainView: View {
    @Environment(AppDependencies.self) private var dependencies
    @SceneStorage("selectedTab") private var selection: AppTab = .capture
    @State private var router = MainWindowRouter.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(AppTab.primary) { tab in
                        Label(tab.title, systemImage: tab.symbolName).tag(tab)
                    }
                }
                Section("Settings") {
                    ForEach(AppTab.settings) { tab in
                        Label(tab.title, systemImage: tab.symbolName).tag(tab)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .focusedSceneValue(\.selectedTab, $selection)
        .toolbar {
            CaptureToolbar(capture: dependencies.capture)
        }
        .onAppear(perform: applyPendingPage)
        .onChange(of: router.pending) { applyPendingPage() }
        .frame(minWidth: 760, minHeight: 500)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .capture:
            CaptureHomeView(showLibrary: { selection = .library })
        case .library:
            LibraryView()
        case .general:
            settingsPage { GeneralSettingsView(launchAtLogin: dependencies.launchAtLogin) }
        case .captureOptions:
            settingsPage { CaptureSettingsView() }
        case .output:
            settingsPage { OutputSettingsView() }
        case .quickAccess:
            settingsPage { QuickAccessSettingsView() }
        case .recording:
            settingsPage { RecordingSettingsView() }
        case .shortcuts:
            settingsPage { ShortcutsSettingsView() }
        case .advanced:
            settingsPage { AdvancedSettingsView() }
        }
    }

    /// Settings forms keep a comfortable reading width in a wide window.
    private func settingsPage(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
    }

    private func applyPendingPage() {
        guard let page = router.pending else { return }
        selection = page
        router.pending = nil
    }
}

extension FocusedValues {
    /// The main window's page, so View menu commands can switch it.
    @Entry var selectedTab: Binding<AppTab>?
}

/// Capture buttons in the window toolbar. macOS groups them on one glass capsule.
private struct CaptureToolbar: ToolbarContent {
    let capture: CaptureCoordinator

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ForEach(QuickAction.screenshots) { action in
                Button(action.title, systemImage: action.symbolName) {
                    Task { await capture.run(action) }
                }
                .help(action.title)
                .disabled(capture.isCapturing)
            }
        }
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    MainView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 960, height: 620)
}
#endif
