import SwiftUI

/// Pages that follow two fingers on the trackpad and settle with the system's scroll physics,
/// kept in step with a picker. Each page scrolls vertically on its own; AppKit locks a gesture
/// to one axis, so the two never fight.
struct PagedTabs<Page: Hashable, Content: View>: View {
    @Binding var selection: Page
    let pages: [Page]
    /// Builds every page up front, so moving between them never waits. For a fixed, small set.
    var loadsAllPages = false
    @ViewBuilder let content: (Page) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: Page?
    /// Where a picker change is heading, so pages passed along the way don't change the selection.
    @State private var destination: Page?
    @State private var offset: CGFloat = 0
    @State private var pageWidth: CGFloat = 1

    private var pageViews: some View {
        ForEach(pages, id: \.self) { page in
            content(page)
                .containerRelativeFrame([.horizontal, .vertical])
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            Group {
                if loadsAllPages {
                    HStack(spacing: 0) { pageViews }
                } else {
                    LazyHStack(spacing: 0) { pageViews }
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
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in offset = x }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = max($0, 1) }
        // When a swipe comes to rest, the page it settled on becomes the selection, so the
        // picker and everything that follows it catch up. Reading where the scroll stopped is
        // what's reliable here; the scroll position binding doesn't always report a swipe.
        .onScrollPhaseChange { _, phase in
            guard phase == .idle else { return }
            let index = min(max(Int((offset / pageWidth).rounded()), 0), pages.count - 1)
            let settled = pages[index]
            destination = nil
            position = settled
            if settled != selection {
                selection = settled
                Haptics.generic()
            }
        }
    }
}

extension View {
    /// The segmented look with a capsule for the chosen item, as in the toolbar. macOS 27 draws it
    /// for tab switching; before that it's a standard segmented picker.
    @ViewBuilder
    func tabPickerStyle() -> some View {
        if #available(macOS 27, *) {
            pickerStyle(.tabs)
        } else {
            pickerStyle(.segmented)
        }
    }
}

extension View {
    /// Segmented choices with the same capsule look as the tabs, for value pickers.
    func capsuleSegmentedStyle() -> some View {
        tabPickerStyle()
    }
}
