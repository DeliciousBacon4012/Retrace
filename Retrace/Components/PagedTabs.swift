import SwiftUI

/// Pages that follow two fingers on the trackpad and settle with the system's scroll physics,
/// kept in step with a picker. Each page scrolls vertically on its own; AppKit locks a gesture
/// to one axis, so the two never fight.
struct PagedTabs<Page: Hashable, Content: View>: View {
    @Binding var selection: Page
    let pages: [Page]
    @ViewBuilder let content: (Page) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: Page?
    /// Where a picker change is heading, so pages passed along the way don't change the selection.
    @State private var destination: Page?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages, id: \.self) { page in
                    content(page)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $position)
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.never)
        .onAppear { position = selection }
        .onChange(of: selection) { old, new in
            guard position != new else { return }
            destination = new
            // Only neighbors slide; a longer jump would flash every page between them.
            let isNeighbor = abs((pages.firstIndex(of: old) ?? 0) - (pages.firstIndex(of: new) ?? 0)) == 1
            withAnimation(isNeighbor && !reduceMotion ? .panel : nil) { position = new }
        }
        .onChange(of: position) { _, new in
            guard let new else { return }
            if let destination {
                if new == destination { self.destination = nil }
            } else if new != selection {
                selection = new
                Haptics.levelChange()
            }
        }
    }
}

extension View {
    /// macOS 27's segmented tabs, which VoiceOver announces as tabs; a segmented picker before it.
    @ViewBuilder
    func tabPickerStyle() -> some View {
        if #available(macOS 27, *) {
            pickerStyle(.tabs)
        } else {
            pickerStyle(.segmented)
        }
    }
}
