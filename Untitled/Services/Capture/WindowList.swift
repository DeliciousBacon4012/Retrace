import AppKit

/// A window that can be picked for a window capture.
nonisolated struct WindowCandidate: Sendable {
    let id: CGWindowID
    /// The window's frame in AppKit screen coordinates (origin at the bottom left of the main display).
    let frame: CGRect
}

/// Reads the on-screen windows, front to back, Untitled's own included (its overlays and
/// panels sit above the normal window layer, so they are never offered).
enum WindowList {
    static func onScreenWindows() -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        return info.compactMap { entry in
            guard
                let number = entry[kCGWindowNumber as String] as? NSNumber,
                let layer = entry[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                bounds.width >= 40, bounds.height >= 40
            else {
                return nil
            }
            if let alpha = entry[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0 {
                return nil
            }
            // Window bounds use a top-left origin; flip them into AppKit coordinates.
            let frame = CGRect(
                x: bounds.minX,
                y: primaryHeight - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
            return WindowCandidate(id: CGWindowID(number.uint32Value), frame: frame)
        }
    }
}
