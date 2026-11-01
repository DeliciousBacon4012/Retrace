import SwiftUI

struct CaptureSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("After capture") {
                Toggle("Copy to clipboard", isOn: $settings.copiesToClipboard)
                Toggle("Save to folder", isOn: $settings.savesToFolder)
                Toggle("Show Quick Access thumbnail", isOn: $settings.showsQuickAccess)
                Toggle("Open in editor", isOn: $settings.opensEditor)
            }

            Section {
                Toggle("Include the pointer", isOn: $settings.includesCursor)
                Toggle("Include window shadow", isOn: $settings.includesWindowShadow)
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
