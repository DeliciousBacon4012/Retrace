import SwiftUI

@main
struct UntitledApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let dependencies = appDelegate.dependencies

        Window("Untitled", id: WindowID.main) {
            MainView()
                .environment(dependencies)
                .environment(dependencies.settings)
        }
        .defaultSize(width: 920, height: 600)
        .commands {
            AppCommands()
        }

        MenuBarExtra("Untitled", systemImage: "camera.aperture") {
            MenuBarContent()
        }

        Settings {
            SettingsView()
                .environment(dependencies)
                .environment(dependencies.settings)
        }
    }
}
