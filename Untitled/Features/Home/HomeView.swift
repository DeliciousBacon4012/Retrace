import AppKit
import Combine
import SwiftUI

/// The landing screen: permission status and quick actions.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        HomeContent(
            viewModel: HomeViewModel(permissions: dependencies.permissions),
            capture: dependencies.capture
        )
    }
}

private struct HomeContent: View {
    @State var viewModel: HomeViewModel
    let capture: CaptureCoordinator

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if viewModel.screenRecording == .notGranted {
                    PermissionCard(viewModel: viewModel)
                        .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.headline)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(QuickAction.all) { action in
                            QuickActionTile(
                                action: action,
                                isEnabled: action.captureMode != nil && !capture.isCapturing
                            ) {
                                if let mode = action.captureMode {
                                    Task { await capture.capture(mode) }
                                }
                            }
                        }
                    }
                    Text("Drag to capture an area, click a window to capture it, or press Escape to cancel.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                SaveLocationRow()
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(.default, value: viewModel.screenRecording)
        }
        .task {
            await viewModel.watchScreenRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Untitled")
                .font(.largeTitle.weight(.semibold))
            Text("Screenshots, recordings, and a replay buffer, all in one place.")
                .font(.title3)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("\(viewModel.availableCount) of \(viewModel.plannedCount) planned features available")
                if viewModel.screenRecording == .granted {
                    Label("Screen Recording allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.callout)
            .foregroundStyle(.tertiary)
        }
    }
}

/// Where captures are saved, with buttons to change it or reveal it.
private struct SaveLocationRow: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save to")
                            .font(.headline)
                        Text(settings.saveFolderURL.path(percentEncoded: false))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Change…") {
                        if let folder = FolderPicker.chooseFolder(startingAt: settings.saveFolderURL) {
                            settings.saveFolderPath = folder.path(percentEncoded: false)
                        }
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([settings.saveFolderURL])
                    }
                }
                Divider()
                HStack(spacing: 16) {
                    Toggle("Save", isOn: $settings.savesToFolder)
                    Toggle("Copy to clipboard", isOn: $settings.copiesToClipboard)
                    Toggle("Show thumbnail", isOn: $settings.showsQuickAccess)
                    Spacer()
                    Picker("Format", selection: $settings.imageFormat) {
                        ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
                .toggleStyle(.checkbox)
            }
            .padding(6)
        }
    }
}

/// Explains why Screen Recording access is needed and notices when it is granted.
private struct PermissionCard: View {
    let viewModel: HomeViewModel

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Screen Recording access needed")
                        .font(.headline)
                    Text("Turn on Untitled in System Settings › Privacy & Security › Screen & System Audio Recording. If macOS offers to quit and reopen, choosing Later is fine: Untitled notices on its own.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Allow Access…") {
                            viewModel.requestScreenRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Open System Settings") {
                            viewModel.openScreenRecordingSettings()
                        }
                        Button {
                            Task { await viewModel.checkAgain() }
                        } label: {
                            if viewModel.isChecking {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Check Again")
                            }
                        }
                        .disabled(viewModel.isChecking)
                    }
                    if !CodeSigningInfo.hasTeamIdentifier {
                        Label {
                            Text("This build is signed only to run locally, so macOS forgets the permission every time it's rebuilt. In Xcode, choose a Team under Signing & Capabilities.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    if viewModel.checkFoundNoAccess {
                        HStack(spacing: 8) {
                            Text("Already turned it on? Some Macs only apply it after a restart.")
                                .foregroundStyle(.secondary)
                            Button("Restart Untitled") {
                                viewModel.restart()
                            }
                            .buttonStyle(.link)
                        }
                        .font(.callout)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }
}

#Preview("Needs permission") {
    let dependencies = AppDependencies.preview()
    HomeView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 700, height: 620)
}

#Preview("Granted") {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    HomeView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 700, height: 620)
}
