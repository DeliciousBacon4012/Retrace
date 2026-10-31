# Untitled

An all-in-one screen utility for macOS: screenshots, annotation, screen recording, and a replay buffer, in one lightweight, native app.

> Early development. Screenshots, the editor, export, text capture, recording, and the replay buffer work today. The in-app **Roadmap** lists everything planned.

## Requirements

- macOS 26 Tahoe or later
- Xcode 27 or later to build

## Build and run

1. Open `Untitled.xcodeproj` in Xcode.
2. Select the **Untitled** scheme and **My Mac**.
3. Press ⌘R.

The first time you capture, macOS asks for Screen Recording access.

## Install as a regular app

A build from ⌘R lives in Xcode's build folder and stops when Xcode stops. To get an `Untitled.app` you can open from Applications, Spotlight, or Login Items:

### In Xcode

1. Open `Untitled.xcodeproj`, click the **Untitled** project in the sidebar, then the **Untitled** target › **Signing & Capabilities**.
2. Turn on **Automatically manage signing** and pick your **Team** (your Apple Account works; add it in Xcode › Settings › Accounts if the list is empty).
3. Choose **Product › Archive**. The Organizer window opens when it's done.
4. Select the new archive and click **Distribute App › Custom › Next › Copy App › Next**, then choose a folder such as Desktop.
5. Drag `Untitled.app` from that folder into **Applications** and open it.

### In Terminal

From the folder that holds `Untitled.xcodeproj`:

```sh
xcodebuild -project Untitled.xcodeproj -scheme Untitled -configuration Release -derivedDataPath build build
ditto build/Build/Products/Release/Untitled.app /Applications/Untitled.app
open /Applications/Untitled.app
```

To update later, quit Untitled, pull the latest code, and run the same commands again.

### Screen Recording permission

macOS ties Screen Recording access to the app's signature. Keep signing with the same team and the permission carries over between updates. If captures come out blank after an update, open System Settings › Privacy & Security › Screen & System Audio Recording, remove Untitled with the minus button, and allow it again.

## Project layout

```
Untitled/
  App/         Entry point, scenes, dependency container
  Features/    One folder per screen: views and view models
  Models/      Plain value types
  Services/    System access behind protocols (permissions, settings, login item)
  Components/  Reusable views
  Resources/   Assets
  Support/     Logging, extensions, small AppKit helpers
```

Views only lay things out, view models hold state, and services do the work behind protocols, so each can be replaced by a mock in previews and tests. There are no third-party dependencies.

## License

MIT. See [LICENSE](LICENSE).
