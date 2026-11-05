import SwiftUI

/// Where the floating thumbnails appear, how they stack, how fast they move, and when they leave.
struct QuickAccessSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Picker("Position", selection: $settings.overlayCorner) {
                    ForEach(OverlayCorner.allCases) { corner in
                        Label(corner.title, systemImage: corner.symbolName).tag(corner)
                    }
                }
                .capsuleSegmentedStyle()
                .labelStyle(.iconOnly)

                Picker("Arrange", selection: $settings.quickAccessLayout) {
                    ForEach(QuickAccessLayout.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()

                Picker("Size", selection: $settings.quickAccessSize) {
                    ForEach(QuickAccessSize.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()

                Picker("Aspect Ratio", selection: $settings.quickAccessAspectRatio) {
                    ForEach(QuickAccessAspectRatio.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()

                LabeledContent("Most shown at once") {
                    HStack(spacing: 8) {
                        Text(settings.quickAccessMaxVisible, format: .number)
                            .monospacedDigit()
                        Stepper("Most shown at once", value: $settings.quickAccessMaxVisible, in: 1...8)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("Layout")
            } footer: {
                Text(settings.quickAccessLayout == .stack
                    ? "Click a thumbnail to edit it, drag it into any app, or flick it toward the screen edge to put it away. Thumbnails crop to the chosen shape, stack in the corner, and rise into a column while the pointer is over them. The capture itself is unchanged. Turn them on or off in Capture."
                    : "Thumbnails crop to the chosen shape in a column, newest nearest the corner. The capture itself is unchanged.")
            }

            Section {
                Picker("Speed", selection: $settings.overlaySpeed) {
                    ForEach(OverlaySpeed.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()

                Picker("Close automatically", selection: $settings.overlayAutoCloseSeconds) {
                    ForEach(SettingsStore.overlayAutoCloseChoices, id: \.self) { seconds in
                        let title = seconds == 0
                            ? String(localized: "Never")
                            : String(localized: "After \(seconds) seconds")
                        Text(title).tag(seconds)
                    }
                }
            } header: {
                Text("Timing")
            } footer: {
                Text("The countdown pauses while the pointer is over the thumbnails.")
            }
        }
        .onChange(of: settings.quickAccessAspectRatio) { dependencies.quickAccess.refreshLayout() }
        .onChange(of: settings.quickAccessSize) { dependencies.quickAccess.refreshLayout() }
        .disabled(!settings.showsQuickAccess)
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview()
    QuickAccessSettingsView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .settingsPage()
}
#endif
