import AppKit
import Combine
import SwiftUI

/// The landing screen: permission status and quick actions.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        HomeContent(viewModel: HomeViewModel(permissions: dependencies.permissions))
    }
}

private struct HomeContent: View {
    @State var viewModel: HomeViewModel

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
                            QuickActionTile(action: action, isEnabled: false) {}
                        }
                    }
                    Text("Capture tools arrive in the next update. The Roadmap tab lists everything planned.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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
    HomeView()
        .environment(AppDependencies.preview())
        .frame(width: 700, height: 520)
}

#Preview("Granted") {
    HomeView()
        .environment(AppDependencies.preview(screenRecording: .granted))
        .frame(width: 700, height: 520)
}
