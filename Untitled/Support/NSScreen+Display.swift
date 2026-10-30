import AppKit

extension NSScreen {
    /// The Core Graphics display ID of this screen.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The screen under the mouse pointer, falling back to the main screen.
    static var underPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }

    /// Converts a rect in AppKit screen coordinates to points relative to this screen's top-left corner.
    func topLeftRelativeRect(for rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - frame.minX,
            y: frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
