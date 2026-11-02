import AppKit
import SwiftUI

/// Explains why Screen Recording access is needed, above Recents, until it's granted.
/// It's a notice in the content, so it uses a plain fill rather than glass.
struct PermissionBanner: View {
    let model: ScreenRecordingAccessModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Recording Access Needed")
                        .font(.headline)
                    Text("Turn on Untitled in System Settings › Privacy & Security › Screen & System Audio Recording. If macOS offers to quit and reopen, Later is fine: Untitled notices on its own.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Allow Access…") { model.requestScreenRecording() }
                    .buttonStyle(.borderedProminent)
                Button("Open System Settings") { model.openScreenRecordingSettings() }
                Spacer()
                Button {
                    Task { await model.checkAgain() }
                } label: {
                    if model.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check Again")
                    }
                }
                .disabled(model.isChecking)
            }
            .controlSize(.small)

            if !CodeSigningInfo.hasTeamIdentifier {
                Text("This build is signed only to run locally, so macOS forgets the permission each time it's rebuilt. In Xcode, choose a Team under Signing & Capabilities.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.checkFoundNoAccess {
                HStack(spacing: 6) {
                    Text("Already turned it on? Some Macs only apply it after a restart.")
                        .foregroundStyle(.secondary)
                    Button("Restart Untitled") { model.restart() }
                        .buttonStyle(.link)
                }
                .font(.callout)
            }
        }
        .padding(14)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
    }
}
