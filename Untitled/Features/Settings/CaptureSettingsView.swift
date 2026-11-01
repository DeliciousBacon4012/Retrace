import SwiftUI

/// How screenshots are taken.
struct CaptureSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Include the pointer", isOn: $settings.includesCursor)
                Toggle("Include window shadow", isOn: $settings.includesWindowShadow)
            } footer: {
                Text("The window shadow applies to window captures. Recordings always show the pointer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
#Preview {
    CaptureSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
#endif
