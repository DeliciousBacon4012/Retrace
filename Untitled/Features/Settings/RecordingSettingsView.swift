import SwiftUI

/// How screen recordings are encoded and which audio they include.
struct RecordingSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Group {
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
                Picker("Countdown", selection: $settings.recordingCountdownSeconds) {
                    Text("Off").tag(0)
                    Text("3 s").tag(3)
                    Text("5 s").tag(5)
                }
                .pickerStyle(.segmented)
                Toggle("Show time in the menu bar", isOn: $settings.showsRecordingTimeInMenuBar)
            } footer: {
                Text("The countdown appears in the menu bar; click it to cancel. While recording, a red dot and the time so far appear there; click them to stop.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview {
    RecordingSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .settingsPage()
}
#endif
