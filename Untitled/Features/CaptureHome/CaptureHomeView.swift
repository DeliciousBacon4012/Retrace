import AppKit
import Combine
import SwiftUI

/// The Capture tab: permission status, the capture buttons, recent captures,
/// and where new ones are saved.
struct CaptureHomeView: View {
    let showLibrary: () -> Void

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        CaptureHomeContent(
            viewModel: CaptureHomeViewModel(permissions: dependencies.permissions),
            capture: dependencies.capture,
            recording: dependencies.recording,
            library: dependencies.library,
            showLibrary: showLibrary
        )
    }
}

private struct CaptureHomeContent: View {
    @State var viewModel: CaptureHomeViewModel
    let capture: CaptureCoordinator
    let recording: RecordingCoordinator
    let library: CaptureLibrary
    let showLibrary: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if viewModel.screenRecording == .notGranted {
                    PermissionCard(viewModel: viewModel)
                        .transition(.blurReplace)
                }

                section("Take a Screenshot") {
                    HStack(spacing: 12) {
                        ForEach(QuickAction.screenshots) { action in
                            CaptureButton(action: action, title: action.title, isDisabled: capture.isCapturing) {
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

                section("Record the Screen") {
                    HStack(spacing: 12) {
                        ForEach(QuickAction.recordings) { action in
                            CaptureButton(
                                action: action,
                                title: recording.isRecording ? String(localized: "Stop Recording") : action.title,
                                isDisabled: recording.recorder.state == .starting || recording.recorder.state == .finishing
                            ) {
                                if let mode = action.recordingMode {
                                    Task { await recording.toggle(mode) }
                                }
                            }
                        }
                    }
                }

                if !library.items.isEmpty {
                    section("Recent") {
                        RecentCapturesRow(items: Array(library.items.prefix(8)), showLibrary: showLibrary)
                    }
                }

                SaveLocationRow()
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(.smooth, value: viewModel.screenRecording)
        }
        .task {
            await viewModel.watchScreenRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refresh()
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }
}

/// A large button for one capture mode, with its keyboard shortcut underneath.
private struct CaptureButton: View {
    let action: QuickAction
    let title: String
    let isDisabled: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            VStack(spacing: 8) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 26, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 32)
                Text(title)
                    .font(.body.weight(.medium))
                    .contentTransition(.interpolate)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .controlSize(.extraLarge)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .disabled(isDisabled)
        .help(title)
    }
}

/// The newest captures, side by side. Double-click opens one; drag it into any app.
private struct RecentCapturesRow: View {
    let items: [LibraryItem]
    let showLibrary: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        FileThumbnail(url: item.url, maximumSize: CGSize(width: 220, height: 140))
                            .padding(6)
                            .frame(width: 150, height: 100)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                            .contentShape(.rect)
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
                            .onDrag { NSItemProvider(object: item.url as NSURL) }
                            .help(item.name)
                            .accessibilityLabel(item.name)
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .scrollIndicators(.never)
            Button("Show All", action: showLibrary)
                .buttonStyle(.link)
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
    let viewModel: CaptureHomeViewModel

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
    CaptureHomeView(showLibrary: {})
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 760, height: 620)
}

#Preview("Granted") {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    CaptureHomeView(showLibrary: {})
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 760, height: 620)
}
