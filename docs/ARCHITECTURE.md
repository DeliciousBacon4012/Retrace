# Architecture

```
Retrace/
  App/         Entry point, scenes, commands, dependency container, coordinators
  Features/    One folder per screen or panel: views and view models
  Models/      Plain value types
  Services/    System access behind protocols, plus storage and recording
  Components/  Reusable views
  Resources/   Assets and the Icon Composer app icon
  Support/     Design constants, logging, small AppKit helpers
RetraceTests/  Hosted XCTest bundle
```

Views lay things out, view models hold state, and services do the work behind protocols so previews and tests can swap them. `AppDependencies` builds the object graph once and passes it through the environment.

## Windows

- **Main window:** Library and Editor tabs (`Features/Main`).
- **Settings:** the ⌘, scene, with categories in a segmented picker (`Features/Settings`).
- **Editor:** `EditorSession` is one open image. `EditorPresenter` shows it in the Editor tab or in a window of its own (`EditorWindowController`), and can move it from tab to window. In the tab, its tools join the main window's real toolbar while the tab is in front.
- **Floating panels:** the capture overlay, Quick Access thumbnails, toasts, recording HUD, and pins are nonactivating `NSPanel`s hosting SwiftUI. They're excluded from captures.
- **Menu bar extra:** the app's main entry point; it can run with no window open.

## Capture flow

`CaptureCoordinator` runs a capture through ScreenCaptureKit, encodes with ImageIO off the main actor, audits metadata before writing, saves through the `CaptureStorage` actor, and shows Quick Access. `RecordingCoordinator` and `ReplayCoordinator` follow the same shape for movies; output paths are reserved before the writers start.

## Stored data

- Preferences: `SettingsStore` over `UserDefaults`, with values validated on load.
- Application Support/<bundle ID>/: `Clipboard/`, `Originals/`, `Library/CaptureSources.json`, `Text History.json`. Development builds get their own folder through their own bundle ID.
- Captures: Pictures/Retrace by default, plus any folders added in Settings.
