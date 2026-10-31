import SwiftUI

/// Where the floating thumbnails appear, how they stack, how fast they move, and when they leave.
struct QuickAccessSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Show a thumbnail after each capture", isOn: $settings.showsQuickAccess)
            } footer: {
                Text("Double-click a thumbnail to edit it. Drag it into any app, or flick it toward the screen edge to put it away.")
            }

            Section {
                Picker("Position", selection: $settings.overlayCorner) {
                    ForEach(OverlayCorner.allCases) { corner in
                        Label(corner.title, systemImage: corner.symbolName).tag(corner)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)

                Picker("Arrange", selection: $settings.quickAccessLayout) {
                    ForEach(QuickAccessLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Size", selection: $settings.quickAccessSize) {
                    ForEach(QuickAccessSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Stepper(value: $settings.quickAccessMaxVisible, in: 1...8) {
                    LabeledContent("Most shown at once", value: settings.quickAccessMaxVisible, format: .number)
                }
            } header: {
                Text("Layout")
            } footer: {
                Text(settings.quickAccessLayout == .stack
                    ? "Thumbnails stack in the corner and rise into a column while the pointer is over them."
                    : "Thumbnails always stand in a column, newest nearest the corner.")
            }

            Section {
                Picker("Speed", selection: $settings.overlaySpeed) {
                    ForEach(OverlaySpeed.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Close automatically", selection: $settings.overlayAutoCloseSeconds) {
                    Text("Never").tag(0)
                    Text("After 5 seconds").tag(5)
                    Text("After 10 seconds").tag(10)
                    Text("After 30 seconds").tag(30)
                    Text("After 1 minute").tag(60)
                }
            } header: {
                Text("Timing")
            } footer: {
                Text("The countdown pauses while the pointer is over the thumbnails.")
            }
        }
        .formStyle(.grouped)
        .disabled(!settings.showsQuickAccess)
    }
}

#if DEBUG
#Preview {
    QuickAccessSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
#endif
