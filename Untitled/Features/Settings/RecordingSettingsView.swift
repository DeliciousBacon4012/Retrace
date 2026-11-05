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
                    ForEach(SettingsStore.frameRateChoices, id: \.self) { rate in
                        Text("\(rate) fps").tag(rate)
                    }
                }
            }

            Section("Audio") {
                Toggle("Record system audio", isOn: $settings.recordsSystemAudio)
                Toggle("Record microphone", isOn: $settings.recordsMicrophone)
            }

            Section {
                Picker("Countdown", selection: $settings.recordingCountdownSeconds) {
                    ForEach(SettingsStore.recordingCountdownChoices, id: \.self) { seconds in
                        Text(seconds == 0 ? "Off" : "\(seconds) s").tag(seconds)
                    }
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
