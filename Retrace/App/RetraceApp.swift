import SwiftUI

@main
struct RetraceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let dependencies = appDelegate.dependencies

        Window("Retrace", id: WindowID.main) {
            MainView()
                .environment(dependencies)
                .environment(dependencies.settings)
        }
        .defaultSize(width: 1_180, height: 760)
        .windowToolbarStyle(.unified(showsTitle: false))
        // The launch decides whether this opens (see LaunchContext), not window restoration,
        // so starting at login stays in the menu bar.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            AppCommands(dependencies: dependencies)
            EditorCommands(editors: dependencies.editor)
        }

        Settings {
            SettingsView()
                .environment(dependencies)
                .environment(dependencies.settings)
        }
        .windowToolbarStyle(.unified(showsTitle: false))

        MenuBarExtra {
            MenuBarContent()
                .environment(dependencies)
                .environment(dependencies.settings)
        } label: {
            MenuBarLabel(recording: dependencies.recording, settings: dependencies.settings)
                .modifier(LaunchWindowPresenter(launch: appDelegate.launch))
                .modifier(WindowRequestPresenter())
        }
    }
}
