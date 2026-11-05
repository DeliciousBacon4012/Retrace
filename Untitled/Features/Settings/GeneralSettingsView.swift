import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @AppStorage(LibraryViewModel.quickLookOnClickKey) private var quickLookOnClick = false
    @State private var viewModel: GeneralSettingsViewModel

    init(launchAtLogin: any LaunchAtLoginControlling) {
        _viewModel = State(initialValue: GeneralSettingsViewModel(launchAtLogin: launchAtLogin))
    }

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { viewModel.launchesAtLogin },
                    set: { viewModel.setLaunchesAtLogin($0) }
                ))
                if let message = viewModel.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Toggle("Open this window when retrace starts", isOn: $settings.opensWindowAtLaunch)
                Toggle("Show icon in the Dock", isOn: $settings.showsDockIcon)
                Toggle("Play sounds", isOn: $settings.playsSounds)
            } footer: {
                Text("When retrace opens at login, it starts in the menu bar only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Preview screenshots and recordings on click", isOn: $quickLookOnClick)
            } header: {
                Text("Library")
            } footer: {
                Text("When off, a single click selects an item. Press Space to preview; double-click opens it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview {
    GeneralSettingsView(launchAtLogin: PreviewLaunchAtLoginService())
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .settingsPage()
}
#endif
