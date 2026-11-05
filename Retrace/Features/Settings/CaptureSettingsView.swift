import SwiftUI

/// How screenshots are taken.
struct CaptureSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Toggle("Include the pointer", isOn: $settings.includesCursor)
            } footer: {
                Text("Recordings show the pointer; Settings › Recording can draw it with motion blur instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Window Captures") {
                Toggle("Shadow", isOn: $settings.includesWindowShadow)
                LabeledContent("Padding") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(settings.windowPadding) },
                            set: { settings.windowPadding = Int($0) }
                        ), in: 0...120, step: 8)
                        Text("\(settings.windowPadding) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Picker("Background", selection: $settings.windowBackground) {
                    ForEach(WindowBackground.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()
            }
        }
    }
}

#if DEBUG
#Preview {
    CaptureSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .settingsPage()
}
#endif
