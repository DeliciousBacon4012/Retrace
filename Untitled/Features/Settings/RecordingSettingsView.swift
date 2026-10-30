import SwiftUI

struct RecordingSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Video") {
                Picker("Codec", selection: $settings.videoCodec) {
                    ForEach(VideoCodec.allCases) { Text($0.title).tag($0) }
                }
                Picker("Frame rate", selection: $settings.framesPerSecond) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
            }

            Section("Audio") {
                Toggle("Record system audio", isOn: $settings.recordsSystemAudio)
                Toggle("Record microphone", isOn: $settings.recordsMicrophone)
            }

            Section {
                Toggle("Keep a replay buffer", isOn: $settings.replayBufferEnabled)
                Picker("Keep the last", selection: $settings.replayBufferSeconds) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                }
                Picker("Size limit", selection: $settings.replayDiskLimitGB) {
                    Text("1 GB").tag(1)
                    Text("2 GB").tag(2)
                    Text("4 GB").tag(4)
                    Text("8 GB").tag(8)
                    Text("16 GB").tag(16)
                }
            } header: {
                Text("Replay Buffer")
            } footer: {
                Text("Untitled quietly records your screen at standard resolution and keeps only the last stretch, in a temporary folder that's cleared when it stops. Save it from the menu bar, the Capture tab, or its shortcut.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    RecordingSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
