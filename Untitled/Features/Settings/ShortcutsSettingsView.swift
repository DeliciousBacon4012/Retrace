import SwiftUI

/// Lists every action that will get a global shortcut. Recording shortcuts arrives in a later step.
struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(QuickAction.all) { action in
                    LabeledContent {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(action.title, systemImage: action.symbolName)
                    }
                }
            } footer: {
                Text("You'll be able to set a shortcut for each action once capture is available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ShortcutsSettingsView()
        .frame(width: 520)
}
