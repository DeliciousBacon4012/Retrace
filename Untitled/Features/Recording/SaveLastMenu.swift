import SwiftUI

/// The Save Last choices: each saved length, the whole buffer, and a way to edit the list.
/// Used in the menu bar, the Capture menu, and on the Capture page.
struct SaveLastMenu: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu("Save Last", systemImage: "gobackward") {
            ForEach(settings.saveLastDurations, id: \.self) { seconds in
                Button(Self.title(for: seconds)) {
                    Task { await dependencies.replay.saveClip(lastSeconds: seconds) }
                }
                .menuShortcut(settings.shortcuts[QuickAction.saveLast(seconds).id])
                // The buffer never holds more than its own length.
                .disabled(seconds > settings.replayBufferSeconds)
            }
            Divider()
            Button("Entire Buffer") {
                Task { await dependencies.replay.saveClip() }
            }
            .menuShortcut(settings.shortcuts["saveReplay"])
            Divider()
            Button("Edit Durations…") {
                MainWindowRouter.shared.showSettings(.recording, using: openSettings)
            }
        }
        .disabled(!dependencies.replay.buffer.isOn || dependencies.replay.buffer.state == .saving)
    }

    /// "15 seconds" or "1 minute".
    static func title(for seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}
