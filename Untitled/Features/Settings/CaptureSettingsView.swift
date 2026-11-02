import SwiftUI

/// How screenshots are taken.
struct CaptureSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Toggle("Include the pointer", isOn: $settings.includesCursor)
                Toggle("Include window shadow", isOn: $settings.includesWindowShadow)
            } footer: {
                Text("The window shadow applies to window captures. Recordings always show the pointer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
