import SwiftUI

/// The standard Settings window, one tab per topic.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TabView {
            GeneralSettingsView(launchAtLogin: dependencies.launchAtLogin)
                .tabItem { Label("General", systemImage: "gearshape") }
            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
            OutputSettingsView()
                .tabItem { Label("Output", systemImage: "folder") }
            RecordingSettingsView()
                .tabItem { Label("Recording", systemImage: "record.circle") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

/// A footer explaining that a pane's settings are stored ahead of the features that use them.
struct PendingFeatureFooter: View {
    var body: some View {
        Text("These settings are saved now and take effect as each feature ships.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview()
    SettingsView()
        .environment(dependencies)
        .environment(dependencies.settings)
}
#endif
