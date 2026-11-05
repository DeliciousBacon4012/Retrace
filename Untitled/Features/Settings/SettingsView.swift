import SwiftUI

/// Native Settings scene with the same category sidebar and page content used in the workspace.
struct SettingsView: View {
    @AppStorage(SettingsPane.storageKey) private var selection: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsCategorySidebar(selection: $selection)
                .frame(width: 220)
            Divider()
            SettingsPageContent(pane: selection)
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

struct SettingsCategorySidebar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsPane.allCases) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(pane)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
    }
}

struct SettingsPageContent: View {
    let pane: SettingsPane

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        page(for: pane)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(pane.title)
    }

    @ViewBuilder
    private func page(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            Group {
                GeneralSettingsView(launchAtLogin: dependencies.launchAtLogin)
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.displayVersion)
                }
            }
            .settingsPage()
        case .capture:
            Group {
                CaptureSettingsView()
                AfterCaptureSettingsView()
                FilesPrivacySettingsView()
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
