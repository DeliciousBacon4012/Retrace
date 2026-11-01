import SwiftUI

/// What happens to each screenshot once it's taken.
struct AfterCaptureSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Copy to clipboard", isOn: $settings.copiesToClipboard)
                Toggle("Save to folder", isOn: $settings.savesToFolder)
                Toggle("Show Quick Access thumbnail", isOn: $settings.showsQuickAccess)
                Toggle("Open in editor", isOn: $settings.opensEditor)
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
#Preview {
    AfterCaptureSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
#endif
