import SwiftUI

/// Toasts: whether they show, where, and how long each kind stays.
struct NotificationsSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Toggle("Show toasts", isOn: $settings.showsToasts)
                Picker("Position", selection: $settings.toastPosition) {
                    ForEach(ToastPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.showsToasts)
            } footer: {
                Text("Toasts are short notices at the top of the screen, such as “Copied 3 lines”. Hover over one to keep it and see what you can do with it, or click it to close it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Lines of captured text shown", selection: $settings.toastPreviewLines) {
                    ForEach(1...5, id: \.self) { lines in
                        Text(lines, format: .number).tag(lines)
                    }
                }
                .disabled(!settings.showsToasts)
                Picker("Open text in", selection: $settings.plainTextApp) {
                    ForEach(PlainTextApp.allCases) { app in
                        Text(app.title).tag(app)
                    }
                }
            } header: {
                Text("Captured Text")
            } footer: {
                Text("Text opens as a plain .txt file, from toasts and from Recents.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ToastKind.allCases) { kind in
                    Picker(kind.title, selection: seconds(for: kind)) {
                        ForEach(ToastKind.secondsChoices, id: \.self) { seconds in
                            Text(ToastKind.label(forSeconds: seconds)).tag(seconds)
                        }
                    }
                }
            } header: {
                Text("Time on Screen")
            } footer: {
                Text("Image, saved and recording toasts appear only when Quick Access is off, since its thumbnails already show each capture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.showsToasts)
        }
    }

    private func seconds(for kind: ToastKind) -> Binding<Int> {
        Binding {
            settings.toastSeconds(for: kind)
        } set: { newValue in
            settings.setToastSeconds(newValue, for: kind)
        }
    }
}

#if DEBUG
#Preview {
    NotificationsSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .settingsPage()
}
#endif
