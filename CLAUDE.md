# Retrace

A native macOS screen utility: screenshots, annotation, recording, a replay buffer, and clipboard history. SwiftUI, Swift 6, macOS 26+, no third-party dependencies.

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code fits together and [docs/STATUS.md](docs/STATUS.md) for what's verified. [docs/FEATURES.md](docs/FEATURES.md) is the owner's wishlist, and its rules bind every change. [docs/UI-NAMES.md](docs/UI-NAMES.md) lists the names the owner uses for UI parts. `docs/history/` is an archive; don't add to it or treat it as current.

## Rules

- Use Apple's newest native Liquid Glass and material APIs only. Never imitate glass with blurs, gradients, or stacked shapes. Check the current docs before using a new API.
- Follow Apple's material rules: glass is for controls and navigation floating above content, never in the content layer, and never on top of other glass. Standard controls get it for free. Custom `glassEffect` goes on floating controls, inside a `GlassEffectContainer` when they sit together. Use standard materials on content such as Library thumbnails. Use `.clear` glass only over media, with a 35% dim if it's bright.
- Follow Apple's trackpad conventions: two-finger swipes between pages, pinch to zoom, force click for Quick Look, two-finger double-tap for smart zoom. Don't redefine system gestures. Haptics use Apple's Mac patterns: alignment for snaps and limits, generic otherwise.
- Motion comes from `Animation.response`, `.panel`, and `.pop` in `Support/Design.swift`, and honors Reduce Motion. No linear or keyframe-looking animation.
- Every screen handles keyboard, pointer, trackpad gestures, VoiceOver, and light and dark mode.
- Anything that can be a preference is one, and it persists.
- Don't call something done because it builds. Run it and click through it.
- Keep one doc for each job. Update STATUS.md instead of writing dated logs.

## Building

- In Xcode: open `Retrace.xcodeproj`, use the Retrace scheme, and run on My Mac.
- Test builds without signing must use a separate bundle ID. An unsigned copy under the real ID leaves a stale Screen Recording entry:

```sh
xcodebuild -project Retrace.xcodeproj -scheme Retrace -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=io.github.deliciousbacon4012.Retrace.dev test
```

- The `.dev` build has no Screen Recording access and adds a second row in System Settings, so warn the owner before launching it.

## Data

Bundle ID `io.github.deliciousbacon4012.Retrace`. Data lives in Application Support under the bundle ID, captures default to Pictures/Retrace. `LegacyDataMigrator` moves data from the old Untitled name once; keep it until no copy of the old app could remain.
