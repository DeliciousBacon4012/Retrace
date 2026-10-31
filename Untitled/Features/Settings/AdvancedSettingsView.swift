import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var isConfirmingReset = false
    @State private var screenRecording: PermissionStatus = .notGranted

    var body: some View {
        Form {
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
    AdvancedSettingsView()
        .environment(AppDependencies.preview())
        .frame(width: 520)
}
#endif
