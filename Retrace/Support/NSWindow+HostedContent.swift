import AppKit
import SwiftUI

extension NSWindow {
    /// Shows a SwiftUI view in a window whose size the app sets itself, such as a floating panel.
    ///
    /// When an `NSHostingView` is a window's content view, it keeps the window's minimum and
    /// maximum size in step with SwiftUI's layout. In a panel that the app resizes and animates
    /// in the same moment, that can loop until AppKit stops it with an exception ("more Update
    /// Constraints in Window passes than there are views in the window"). Here the hosting view
    /// sits inside a plain view and just fills it, so the window alone decides its size.
    func setHostedContent<Content: View>(_ hosting: NSHostingView<Content>) {
        hosting.sizingOptions = []
        let container = NSView(frame: CGRect(origin: .zero, size: contentRect(forFrameRect: frame).size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        contentView = container
    }
}
