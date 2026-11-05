import SwiftUI

/// How screen recordings are encoded and which audio they include.
struct RecordingSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Picker("Preset", selection: Binding(
                    get: { settings.recordingPreset },
                    set: { if let preset = $0 { settings.apply(preset) } }
                )) {
                    ForEach(RecordingPreset.allCases) { Text($0.title).tag(RecordingPreset?.some($0)) }
                    if settings.recordingPreset == nil {
                        Divider()
                        Text("Custom").tag(RecordingPreset?.none)
                    }
                }
            } footer: {
                Text("Studio records ProRes for editing, and its files are large. Better Performance uses the least power and space. Changing any setting below makes this Custom.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Codec", selection: $settings.videoCodec) {
                    ForEach(VideoCodec.allCases) { Text($0.title).tag($0) }
                }
                Picker("Frame rate", selection: $settings.framesPerSecond) {
                    ForEach(SettingsStore.frameRateChoices, id: \.self) { rate in
                        Text("\(rate) fps").tag(rate)
                    }
                }
                Picker("Color", selection: $settings.videoColor) {
                    ForEach(VideoColor.allCases) { Text($0.title).tag($0) }
                }
                Picker("Quality", selection: $settings.videoQuality) {
                    ForEach(VideoQuality.allCases) { Text($0.title).tag($0) }
                }
                Picker("Encoder", selection: $settings.videoEncoder) {
                    ForEach(VideoEncoderChoice.allCases) { Text($0.title).tag($0) }
                }
                Stepper(value: $settings.captureQueueDepth, in: SettingsStore.captureQueueDepthRange) {
                    LabeledContent("Frame buffer", value: "\(settings.captureQueueDepth) frames")
                }
            } header: {
                Text("Video")
            } footer: {
                Text("Original keeps what the screen recorder writes. Any other quality re-encodes the movie once you stop, so saving takes a little longer. A larger frame buffer rides out busy moments and uses more memory.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show clicks", isOn: $settings.showsClicks)
                Toggle(isOn: $settings.cursorBlurEnabled) {
                    HStack(spacing: Design.spacingS) {
                        Text("Motion blur on the cursor")
                        Text("Experimental")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    }
                }
                if settings.cursorBlurEnabled {
                    Picker("Blur mode", selection: $settings.cursorBlurMode) {
                        ForEach(CursorBlurMode.allCases) { Text($0.title).tag($0) }
                    }
                    .capsuleSegmentedStyle()
                    LabeledContent("Amount") {
                        Slider(value: $settings.cursorBlurAmount, in: SettingsStore.cursorBlurAmountRange) {
                            Text("Amount")
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                        Text(settings.cursorBlurAmount, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Cursor")
            } footer: {
                Text("Motion blur hides the live cursor and draws it again after you stop, so saving takes longer. It applies to screen and area recordings. Fast blurs along its direction of travel. Quality follows its true path. 50% matches a film camera's 180° shutter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                .capsuleSegmentedStyle()
                Toggle("Show time in the menu bar", isOn: $settings.showsRecordingTimeInMenuBar)
                Toggle("Show Retrace's windows in recordings", isOn: $settings.showsRetraceInRecordings)
                Toggle("Hide Retrace's notices while recording", isOn: $settings.hidesNoticesWhileRecording)
            } footer: {
                Text("The countdown appears in the menu bar; click it to cancel. While recording, a red dot and the time so far appear there; click them for recording options. The recording controls and outline never appear in the movie; Retrace's other windows do unless you turn that off, and it applies to the replay buffer too. To quiet other apps, turn on a Focus in Control Center.")
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
