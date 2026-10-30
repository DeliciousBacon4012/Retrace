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
            AppCommands(capture: dependencies.capture, settings: dependencies.settings)
        }

        Window("Feature Roadmap", id: WindowID.roadmap) {
            NavigationStack {
                RoadmapView()
            }
        }
        .defaultSize(width: 760, height: 560)

        MenuBarExtra("Untitled", systemImage: "camera.aperture") {
            MenuBarContent()
                .environment(dependencies)
                .environment(dependencies.settings)
        }

        Settings {
            SettingsView()
                .environment(dependencies)
                .environment(dependencies.settings)
        }
    }
}
