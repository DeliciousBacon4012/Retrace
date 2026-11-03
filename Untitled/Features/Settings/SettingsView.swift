import SwiftUI

/// The Settings window (⌘,): a toolbar of tabs, each a grouped form. It reopens on the
/// tab last used, and other places can choose a tab through `MainWindowRouter.showSettings`.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @AppStorage(SettingsPane.storageKey) private var selection: SettingsPane = .general

    var body: some View {
        TabView(selection: $selection) {
            ForEach(SettingsPane.allCases) { pane in
                Tab(pane.title, systemImage: pane.symbolName, value: pane) {
                    page(for: pane)
                }
            }
        }
        .frame(width: 560, height: 540)
    }

    /// Related topics share a tab, one after the other in the same form.
    @ViewBuilder
    private func page(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            Group {
                GeneralSettingsView(launchAtLogin: dependencies.launchAtLogin)
                FilesPrivacySettingsView()
            }
            .settingsPage()
        case .capture:
            Group {
                CaptureSettingsView()
                AfterCaptureSettingsView()
            }
            .settingsPage()
        case .quickAccess:
            QuickAccessSettingsView().settingsPage()
        case .clipboard:
            ClipboardSettingsView().settingsPage()
        case .notifications:
            NotificationsSettingsView().settingsPage()
        case .editor:
            EditorSettingsView().settingsPage()
        case .recording:
            Group {
                RecordingSettingsView()
                ReplayBufferSettingsView()
            }
            .settingsPage()
        case .shortcuts:
            ShortcutsSettingsView().settingsPage()
        case .advanced:
            AdvancedSettingsView().settingsPage()
        }
    }
}

extension View {
    /// Puts settings sections in the standard grouped form.
    func settingsPage() -> some View {
        Form { self }
            .formStyle(.grouped)
    }
}
