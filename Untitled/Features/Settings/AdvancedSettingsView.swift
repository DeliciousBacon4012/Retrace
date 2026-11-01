import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @State private var isConfirmingReset = false
    @State private var isConfirmingClearText = false
    @State private var screenRecording: PermissionStatus = .notGranted

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Text history", selection: $settings.textHistoryLimit) {
                    ForEach(SettingsStore.textHistoryLimits, id: \.self) { limit in
                        if limit == 0 {
                            Text("Off").tag(limit)
                        } else {
                            Text("Last \(limit)").tag(limit)
                        }
                    }
                }
                Button("Clear Text History…") {
                    isConfirmingClearText = true
                }
                .disabled(dependencies.textHistory.snippets.isEmpty)
                .confirmationDialog("Clear text history?", isPresented: $isConfirmingClearText) {
                    Button("Clear", role: .destructive) {
                        dependencies.textHistory.removeAll()
                    }
                } message: {
                    Text("Every saved snippet is removed from Recents and the menu bar. Your clipboard isn't affected.")
                }
            } header: {
                Text("History")
            } footer: {
                Text("Text you capture stays on this Mac, in Untitled's own folder rather than your save folder. Lowering the number removes the oldest snippets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    HStack {
                        Text(screenRecording == .granted ? "Allowed" : "Not allowed")
                            .foregroundStyle(.secondary)
                        Button("Open System Settings") {
                            dependencies.permissions.openScreenRecordingSettings()
                        }
                    }
                }
            }

            Section {
                Button("Reset All Settings…", role: .destructive) {
                    isConfirmingReset = true
                }
                .confirmationDialog(
                    "Reset all settings?",
                    isPresented: $isConfirmingReset
                ) {
                    Button("Reset", role: .destructive) {
                        dependencies.settings.resetToDefaults()
                    }
                } message: {
                    Text("Every preference returns to its default. Your captures are not affected.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            screenRecording = dependencies.permissions.screenRecordingStatus
        }
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview()
    AdvancedSettingsView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 520)
}
#endif
