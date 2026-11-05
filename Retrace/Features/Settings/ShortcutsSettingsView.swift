import SwiftUI

/// A global shortcut for every action, recorded by pressing the keys.
struct ShortcutsSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            Section("Screenshots") {
                ForEach(QuickAction.all.filter(\.isScreenshot)) { row(for: $0) }
            }
            Section("Recording") {
                ForEach(QuickAction.recordings) { row(for: $0) }
                ForEach(QuickAction.all.filter { $0.startsOrDiscardsRecording || $0.savesRecording }) { row(for: $0) }
            }
            Section {
                ForEach(QuickAction.all.filter { $0.togglesReplay || $0.savesDefaultReplay || $0.savesReplay }) { row(for: $0) }
                ForEach(settings.saveLastDurations.map(QuickAction.saveLast)) { row(for: $0) }
            } header: {
                Text("Replay")
            } footer: {
                Text("Each Save Last length can have its own shortcut. Change the lengths in Replay Buffer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(QuickAction.all.filter(\.opensClipboard)) { row(for: $0) }
            } header: {
                Text("Other")
            } footer: {
                Text("Shortcuts work from any app. Press Delete while recording to remove one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Use Recommended Shortcuts") {
                    settings.shortcuts = SettingsStore.defaultShortcuts
                }
                Button("Open Keyboard Shortcuts in System Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } footer: {
                Text("Recommended: ⇧⌘2 window, ⇧⌘3 screen, ⇧⌘4 area, ⇧⌘5 replay buffer on or off, ⇧⌘6 start a screen recording (press again to discard it), ⇧⌘7 stop and save, ⇧⌘0 save the replay buffer. macOS uses ⇧⌘3, ⇧⌘4, and ⇧⌘5 for its own screenshots until you turn those off under Keyboard Shortcuts › Screenshots.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func row(for action: QuickAction) -> some View {
        let isAvailable = action.isAvailable
        LabeledContent {
            ShortcutRecorder(shortcut: binding(for: action.id)) { recording in
                dependencies.shortcuts.setPaused(recording)
            }
            .disabled(!isAvailable)
        } label: {
            // A fixed-width icon, so every title starts in the same place.
            Label {
                Text(action.title)
            } icon: {
                Image(systemName: action.symbolName)
                    .frame(width: 20)
            }
            if let problem = dependencies.shortcuts.problems[action.id] {
                Text(problem)
                    .foregroundStyle(.red)
            } else if !isAvailable {
                Text("Coming soon")
            }
        }
    }

    private func binding(for actionID: String) -> Binding<Shortcut?> {
        Binding {
            settings.shortcuts[actionID]
        } set: { newValue in
            var shortcuts = settings.shortcuts
            // A shortcut can only do one thing, so it moves from any other action.
            if let newValue {
                for (otherID, shortcut) in shortcuts where shortcut == newValue && otherID != actionID {
                    shortcuts[otherID] = nil
                }
            }
            shortcuts[actionID] = newValue
            settings.shortcuts = shortcuts
        }
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview()
    ShortcutsSettingsView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .settingsPage()
}
#endif
