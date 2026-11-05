import SwiftUI

/// The ⌘, window: categories in a segmented picker up top, and two-finger swipes between them.
struct SettingsView: View {
    @AppStorage(SettingsPane.storageKey) private var pane: SettingsPane = .general

    var body: some View {
        PagedTabs(selection: $pane, pages: SettingsPane.allCases) { pane in
            SettingsPageContent(pane: pane)
        }
        // In a bar under the title, because eight tabs don't fit a Settings window's toolbar.
        .safeAreaBar(edge: .top) {
            Picker("Settings Category", selection: $pane) {
                ForEach(SettingsPane.allCases) { pane in
                    Text(pane.title).tag(pane)
                }
            }
            .tabPickerStyle()
            .labelsHidden()
            .controlSize(.large)
            .padding(.horizontal, Design.spacingL)
            .padding(.vertical, Design.spacingS)
        }
        .frame(width: 820, height: 600)
        .navigationTitle(pane.title)
    }
}

/// One category, as a standard grouped form that scrolls by itself.
struct SettingsPageContent: View {
    let pane: SettingsPane

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Group {
            switch pane {
            case .general:
                GeneralSettingsView(launchAtLogin: dependencies.launchAtLogin)
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.displayVersion)
                }
            case .capture:
                CaptureSettingsView()
                AfterCaptureSettingsView()
                FilesPrivacySettingsView()
            case .quickAccess:
                QuickAccessSettingsView()
                NotificationsSettingsView()
            case .clipboard:
                ClipboardSettingsView()
            case .editor:
                EditorSettingsView()
            case .recording:
                RecordingSettingsView()
                ReplayBufferSettingsView()
            case .shortcuts:
                ShortcutsSettingsView()
            case .advanced:
                AdvancedSettingsView()
            }
        }
        .settingsPage()
    }
}

extension View {
    /// The standard grouped form System Settings uses, with switches for toggles.
    func settingsPage() -> some View {
        Form { self }
            .formStyle(.grouped)
            .toggleStyle(.switch)
    }
}
