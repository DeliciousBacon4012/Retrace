# Status

Update this file in place. Don't add dated logs.

## Checked by running the app

Run on macOS 27 with an unsigned development build, which has no Screen Recording access:

- Library and Editor tabs, the tab picker, and search appearing only on the Library tab
- Drag on empty space to select several thumbnails
- Settings window with category icons along the top and their pages
- Opening an image in an editor window, with the whole toolbar visible at the minimum width
- Inspector rows lining up

All unit tests pass, including the move from the old Untitled data locations using temporary folders.

## Needs a person with a trackpad and a signed build

- First launch of the signed app: settings, clipboard history, and captures carried over from Untitled
- Two-finger swipes between tabs and between Settings categories, and how they feel
- Pinch to resize thumbnails; force click for Quick Look; two-finger double-tap in the editor; haptics on tab changes, zoom stops, docking the inspector, and flicking a thumbnail
- Glass morphing on toast actions and the crop buttons; not yet seen moving
- Quick Access thumbnails, toasts, the recording HUD, and pins, since they need a real capture
- Cursor motion blur and the quality re-encode in a real recording. Their rendering is tested on generated movies only, and how closely the cursor lines up with the video needs a real look
- Encoder, ProRes, color, 120 fps, and replay settings in a real recording
- Search inside images and Find Similar on your own captures
- Space-drag and middle-button panning, and drag selection scrolling at the window's edge
- Capture and recording modes beyond one area screenshot and one short area movie
- VoiceOver and keyboard-only use

## Known gaps

- The Editor tab is a starting point; each image still opens in its own window.
- Signing: `security find-identity` showed no valid identities on 2026-11-05 and strict `codesign` verification fails, so the build is local only. Distribution isn't set up, and App Sandbox is off.
- `xcodebuild analyze` fails in actool on the Icon Composer file.
- Rendering performance has not been measured with Instruments.
- An unanswered Apple developer forum post reports that only the key window shows active Liquid Glass. If so, nonactivating panels like thumbnails and toasts may look slightly flatter. No confirmed workaround; check it live.
