import SwiftUI

/// A global shortcut for every action, recorded by pressing the keys.
struct ShortcutsSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(QuickAction.all) { action in
                    row(for: action)
                }
            } footer: {
                Text("Shortcuts work from any app. Press Delete while recording to remove one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Default Shortcuts") {
                    settings.shortcuts = SettingsStore.defaultShortcuts
                }
            }
        }
        .formStyle(.grouped)
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
            Label(action.title, systemImage: action.symbolName)
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

#Preview {
    let dependencies = AppDependencies.preview()
    ShortcutsSettingsView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 520)
}
