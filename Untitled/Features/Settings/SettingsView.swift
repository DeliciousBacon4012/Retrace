import SwiftUI

/// Native Settings scene with the Editor's compact, icon-led segmented navigation.
struct SettingsView: View {
    @AppStorage(SettingsPane.storageKey) private var selection: SettingsPane = .general

    var body: some View {
        SettingsPageContent(pane: selection)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Settings Categories", selection: $selection) {
                        ForEach(SettingsPane.allCases) { pane in
                            Label(pane.title, systemImage: pane.symbolName)
                                .help(pane.title)
                                .tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Settings Categories")
                    .frame(width: 540)
                }
            }
            .navigationTitle("Settings")
            .frame(minWidth: 880, minHeight: 600)
    }
}

struct SettingsPageContent: View {
    let pane: SettingsPane

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ScrollView {
            HStack(alignment: .top) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 18) {
                    Text(pane.title)
                        .font(.title2.weight(.semibold))

                    page(for: pane)
                }
                .frame(maxWidth: 800, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    /// Keeps settings controls in the macOS vertical form layout without grouped card rows.
    func settingsPage() -> some View {
        Form { self }
            .formStyle(.automatic)
            .toggleStyle(.switch)
            .buttonStyle(.glass)
            .scrollContentBackground(.hidden)
    }
}
