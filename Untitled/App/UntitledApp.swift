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
        // The launch decides whether this opens (see LaunchContext), not window restoration,
        // so starting at login stays in the menu bar.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            AppCommands(dependencies: dependencies)
        }

        Window("Feature Roadmap", id: WindowID.roadmap) {
            NavigationStack {
                RoadmapView()
            }
        }
        .defaultSize(width: 760, height: 560)

        MenuBarExtra {
            MenuBarContent()
                .environment(dependencies)
                .environment(dependencies.settings)
        } label: {
            MenuBarLabel(recording: dependencies.recording, replay: dependencies.replay, settings: dependencies.settings)
                .modifier(LaunchWindowPresenter(launch: appDelegate.launch))
        }
    }
}
