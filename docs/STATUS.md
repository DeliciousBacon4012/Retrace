# Status

Update this file in place. Don't add dated logs.

## Checked by running the app

Run on macOS 27 with an unsigned development build, which has no Screen Recording access:

- Library and Editor tabs, the tab picker, and search appearing only on the Library tab
- Drag on empty space to select several thumbnails
- Settings window with category icons along the top and their pages
- Opening an image in the Editor tab, keeping marks across tab switches, and moving it to a window
- The editor window's whole toolbar visible at the minimum width
- Inspector rows lining up

All unit tests pass, including the move from the old Untitled data locations using temporary folders.

Main-thread stalls, measured with the debug hang detector on 2026-11-05: none over 100 ms while switching tabs, scrolling, drag-selecting, indexing the Library in the background, or drawing marks on, blurring, and copying a 5120 × 2880 image. Launch had one stall of about 250 ms. Debug builds logged 130 to 300 ms when switching to a full Library or opening a new editor window; these are unoptimized builds, and Release should be faster, but that hasn't been measured. Window resizing, real captures, and recordings weren't measured.

Checked on 2026-11-05 in the test copy: Settings word tabs and capsule pickers, every Settings page, Cancel and Reopen Canceled Image, the canvas moving aside for a floating inspector, and the inspector's header and buttons.

## Needs a person with a trackpad and a signed build

- First launch of the signed app: settings, clipboard history, and captures carried over from Untitled
- Two-finger swipes between tabs and between Settings categories, and how they feel
- Pinch to resize thumbnails; force click for Quick Look; two-finger double-tap in the editor; haptics on tab changes, zoom stops, docking the inspector, and flicking a thumbnail
- Screen Recording now trusts a working ScreenCaptureKit query when the quick check says no; confirm the banner stays away after granting access
- The Save menu (several folders), Save As, and Done saving without a dialog
- The new shortcuts, discarding with ⇧⌘6, saving with ⇧⌘7, and the buffer pausing during a recording
- The window highlight gliding between windows, and toasts dropping straight in
- Glass morphing on toast actions and the crop buttons; not yet seen moving
- Quick Access thumbnails, toasts, the recording HUD, and pins, since they need a real capture
- Cursor motion blur and the quality re-encode in a real recording. Their rendering is tested on generated movies only, and how closely the cursor lines up with the video needs a real look
- Encoder, ProRes, color, 120 fps, and replay settings in a real recording
- Search inside images and Find Similar on your own captures
- Translate in the Library's right-click menu
- Done, Close, and unsaved-changes handling for an image in the Editor tab
- Space-drag and middle-button panning, and drag selection scrolling at the window's edge
- Capture and recording modes beyond one area screenshot and one short area movie
- VoiceOver and keyboard-only use

## Known gaps

- Signing: `security find-identity` showed no valid identities on 2026-11-05 and strict `codesign` verification fails, so the build is local only. Distribution isn't set up, and App Sandbox is off.
- `xcodebuild analyze` fails in actool on the Icon Composer file.
- Rendering performance has not been measured with Instruments.
- An unanswered Apple developer forum post reports that only the key window shows active Liquid Glass. If so, nonactivating panels like thumbnails and toasts may look slightly flatter. No confirmed workaround; check it live.
