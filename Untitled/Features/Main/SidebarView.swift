import SwiftUI

/// The main window's sidebar, grouped the way people think about the tools.
struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: SidebarItem.home) {
                Label("Home", systemImage: "house")
            }

            Section("Capture") {
                row(.capture)
                row(.quickAccess)
                row(.clipboard)
                row(.editor)
            }

            Section("Record") {
                row(.recording)
                row(.replayBuffer)
            }

            Section("Organize") {
                row(.library)
                row(.shelf)
                row(.storage)
            }

            Section("More") {
                row(.utilities)
                NavigationLink(value: SidebarItem.roadmap) {
                    Label("Roadmap", systemImage: "map")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Untitled")
    }

    private func row(_ area: FeatureArea) -> some View {
        NavigationLink(value: SidebarItem.area(area)) {
            Label(area.title, systemImage: area.symbolName)
        }
    }
}

#Preview {
    SidebarView(selection: .constant(.home))
        .frame(width: 220, height: 500)
}
