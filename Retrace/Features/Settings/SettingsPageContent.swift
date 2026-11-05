import SwiftUI

/// The ⌘, window: categories in a segmented picker up top, and two-finger swipes between them.
struct SettingsView: View {
    @AppStorage(SettingsPane.storageKey) private var pane: SettingsPane = .general

    var body: some View {
        // Every page is built once when Settings opens, so switching is instant.
        PagedTabs(selection: $pane, pages: SettingsPane.allCases, loadsAllPages: true) { pane in
            SettingsPageContent(pane: pane)
        }
        .frame(width: 900, height: 620)
        .capsuleControls()
        .navigationTitle(pane.title)
        .toolbar {
            // In the toolbar, where the system draws the picker as one glass capsule.
            ToolbarItem(placement: .principal) {
                Picker("Settings Category", selection: $pane) {
                    ForEach(SettingsPane.allCases) { pane in
                        Text(pane.title).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                .fixedSize()
            }
        }
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
                LibrarySearchSettingsView()
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
                VisionSettingsView()
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
