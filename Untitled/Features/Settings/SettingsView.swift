import SwiftUI

/// Native settings window with a standard sidebar and one focused settings form.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @AppStorage(SettingsPane.storageKey) private var selection: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbolName)
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
            .navigationTitle("Settings")
        } detail: {
            page(for: selection)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 560)
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
