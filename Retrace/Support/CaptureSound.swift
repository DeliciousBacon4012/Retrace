import AppKit

/// Plays the system's screenshot sound, if this Mac has it.
enum CaptureSound {
    private static let sound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true)
    }()

    static func play() {
        sound?.stop()
        sound?.play()
    }
}
