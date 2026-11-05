import SwiftUI

/// The always-on replay buffer: whether it runs, how much it keeps, and how much disk it may use.
struct ReplayBufferSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @State private var newDuration = 45

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                // Turning it on goes through the coordinator, which asks for screen access first.
                Toggle("Keep a replay buffer", isOn: Binding(
                    get: { settings.replayBufferEnabled },
                    set: { dependencies.replay.setEnabled($0) }
                ))
            } footer: {
                Text("retrace quietly records your screen at standard resolution and keeps only the last stretch, in a temporary folder that's cleared when it stops. Save it from the menu bar, the Capture page, or its shortcut.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Keep the last", selection: $settings.replayBufferSeconds) {
                    ForEach(SettingsStore.replayBufferDurationChoices, id: \.self) { seconds in
                        Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds]))).tag(seconds)
                    }
                }
                Picker("Size limit", selection: $settings.replayDiskLimitGB) {
                    ForEach(SettingsStore.replayDiskLimitChoices, id: \.self) { gigabytes in
                        Text("\(gigabytes) GB").tag(gigabytes)
                    }
                }
            } footer: {
                Text("The buffer uses the codec and system audio settings from Recording, at up to 30 frames per second.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(settings.saveLastDurations, id: \.self) { seconds in
                    LabeledContent(SaveLastMenu.title(for: seconds)) {
                        Button("Remove", systemImage: "minus.circle") {
                            settings.removeSaveLastDuration(seconds)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Remove \(SaveLastMenu.title(for: seconds))")
                    }
                }
                if settings.saveLastDurations.count < SettingsStore.maximumSaveLastDurations {
                    LabeledContent("Add") {
                        HStack {
                            TextField("Seconds", value: $newDuration, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 56)
                            Text("seconds")
                                .foregroundStyle(.secondary)
                            Button("Add") {
                                settings.addSaveLastDuration(newDuration)
                            }
                            .disabled(!canAdd)
                        }
                    }
                }
            } header: {
                Text("Save Last")
            } footer: {
                Text("These lengths appear under Save Last in the menu bar and on the Capture page. Lengths longer than the buffer keeps are greyed out there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.response, value: settings.saveLastDurations)
    }

    private var canAdd: Bool {
        (1...SettingsStore.longestSaveLastDuration).contains(newDuration)
            && !settings.saveLastDurations.contains(newDuration)
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview()
    ReplayBufferSettingsView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .settingsPage()
}
#endif
