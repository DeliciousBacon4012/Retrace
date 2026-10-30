# Untitled

An all-in-one screen utility for macOS: screenshots, annotation, screen recording, and a replay buffer, in one lightweight, native app.

> Early development. The app shell is in place; capture features arrive in small steps. The in-app **Roadmap** lists everything planned.

## Requirements

- macOS 14 Sonoma or later
- Xcode 27 or later to build

## Build and run

1. Open `Untitled.xcodeproj` in Xcode.
2. Select the **Untitled** scheme and **My Mac**.
3. Press ⌘R.

The first time you capture, macOS asks for Screen Recording access.

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
