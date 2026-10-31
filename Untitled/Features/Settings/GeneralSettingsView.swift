import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel: GeneralSettingsViewModel

    init(launchAtLogin: any LaunchAtLoginControlling) {
        _viewModel = State(initialValue: GeneralSettingsViewModel(launchAtLogin: launchAtLogin))
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
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
                Toggle("Show icon in the Dock", isOn: $settings.showsDockIcon)
                Toggle("Play sounds", isOn: $settings.playsSounds)
            }

            Section {
                LabeledContent("Version", value: Bundle.main.displayVersion)
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
#Preview {
    GeneralSettingsView(launchAtLogin: PreviewLaunchAtLoginService())
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
#endif
