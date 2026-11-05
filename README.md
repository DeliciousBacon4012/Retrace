# Retrace

An all-in-one screen utility for macOS: screenshots, annotation, screen recording, a replay buffer, and clipboard history, in one lightweight, native app.

> Version 1.0.0. See [docs/STATUS.md](docs/STATUS.md) for what's been verified and [docs/FEATURES.md](docs/FEATURES.md) for what's planned.

## Install

1. Download `Retrace-1.0.0.dmg` from [Releases](https://github.com/DeliciousBacon4012/retrace/releases).
2. Open it and drag **Retrace** onto **Applications**.
3. Open Retrace from Applications. If macOS says it can't check the app, open System Settings › Privacy & Security and click **Open Anyway** under the message about Retrace. This happens once, because the app isn't notarized yet.
4. The first capture asks for Screen Recording access. Allow it in System Settings, then quit and reopen Retrace.

## Requirements

- macOS 26 Tahoe or later. macOS 27 gets the newer segmented tab style.
- Xcode 27 or later to build.

## Build from source

1. Open `Retrace.xcodeproj` in Xcode.
2. Select the **Retrace** scheme and **My Mac**.
3. Press ⌘R.

The first time you capture, macOS asks for Screen Recording access.

## Install as a regular app

A build from ⌘R lives in Xcode's build folder and stops when Xcode stops. To get a `Retrace.app` you can open from Applications, Spotlight, or Login Items:

```sh
xcodebuild -project Retrace.xcodeproj -scheme Retrace -configuration Release -derivedDataPath build build
ditto build/Build/Products/Release/Retrace.app /Applications/Retrace.app
open /Applications/Retrace.app
```

To update later, quit Retrace, pull the latest code, and run the same commands again. Keep signing with the same team, because macOS ties Screen Recording access to the app's signature and bundle identifier. If captures come out blank after an update, remove Retrace from System Settings › Privacy & Security › Screen & System Audio Recording and allow it again.

## Using it

- **Main window:** Library and Editor tabs. Swipe with two fingers to move between them, or press ⌘1 and ⌘2.
- **Library:** drag on empty space to select, pinch to resize thumbnails, press Space to preview.
- **Settings:** ⌘, with categories along the top. Swipe with two fingers between them.
- **Editor:** images open in the Editor tab, or in their own window if you prefer. Pinch to zoom, scroll with two fingers to pan.

## More

- [Architecture](docs/ARCHITECTURE.md)
- [Status](docs/STATUS.md)
- [Wishlist](docs/FEATURES.md)
- [UI names](docs/UI-NAMES.md)

## License

MIT. See [LICENSE](LICENSE).
