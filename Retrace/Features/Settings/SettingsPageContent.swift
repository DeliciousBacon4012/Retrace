import SwiftUI

/// The ⌘, window: categories in a segmented picker up top, and two-finger swipes between them.
struct SettingsView: View {
    @AppStorage(SettingsPane.storageKey) private var pane: SettingsPane = .general

    var body: some View {
        PagedTabs(selection: $pane, pages: SettingsPane.allCases) { pane in
            SettingsPageContent(pane: pane)
        }
        // Icons with the current category's name in the title bar, as System Settings names its
        // panes. Each icon's tooltip and VoiceOver label give its name.
        .safeAreaBar(edge: .top) {
            Picker("Settings Category", selection: $pane) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbolName)
                        .help(pane.title)
                        .tag(pane)
                }
            }
            .tabPickerStyle()
            .labelStyle(.iconOnly)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, Design.spacingS)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 680, height: 600)
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
            case .intelligence:
                IntelligenceSettingsView()
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
