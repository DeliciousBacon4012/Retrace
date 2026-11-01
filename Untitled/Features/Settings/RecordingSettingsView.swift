import SwiftUI

/// How screen recordings are encoded and which audio they include.
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
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
#Preview {
    RecordingSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
#endif
