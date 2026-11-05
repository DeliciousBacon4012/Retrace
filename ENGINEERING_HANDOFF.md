# Retrace Engineering Handoff

**Checkpoint:** 2026-11-04
**Repository:** /Users/har/Documents/Developer/untitled-mac
**Branch:** feature/stability-and-performance
**Base:** origin/main at d902835
**Current HEAD:** c7a5097

## Objective and working rules

Polish the existing macOS app into retrace. Preserve the existing repository, project, user data, and ongoing work. Prefer native macOS controls and supported Apple APIs; keep materials functional and restrained. Prioritize privacy, stability, accessibility, diagnosability, and measured performance. Do not reset, discard, amend, rebase, squash, push, or merge history.

## Git and Xcode checkpoint

- The feature branch is seven local commits ahead of origin/main. Remote origin is unchanged: https://github.com/DeliciousBacon4012/untitled-mac.git.
- The current worktree still has 41 modified tracked files and 8 untracked files. These are the existing broad app redesign, Xcode/test setup, current regression tests, and this handoff/roadmap. No remaining worktree changes are staged.
- Xcode is open on the original Untitled.xcodeproj, shared Untitled scheme, and My Mac destination. Targets are Untitled (application) and UntitledTests (hosted XCTest bundle).
- The app product, executable, display name, and app icon are retrace; it builds as retrace.app. Marketing version is 0.1.0, build 1, category Productivity, and minimum macOS is 26.0.
- The project path, project and target names, scheme, Swift module name, bundle identifier (io.github.deliciousbacon4012.Untitled), Application Support domain, existing Pictures/Untitled folder, and Originals storage path remain unchanged to preserve user data, permissions, tests, and existing workflows. Old capture filenames in the Library are user files and were not renamed. The fallback save notice still names Pictures/Untitled because that is the retained path.
- Signing is Automatic with the configured Personal Team and Apple Development identity. No paid distribution certificate was created. The machine currently reports no valid trusted signing identity; Xcode builds and launches the local app, but a verified trusted signature for distribution is not established. App Sandbox is disabled; do not change sandboxing, entitlements, notarization, or update delivery before distribution requirements are settled.
- The supplied layered retrace_app.icon and menu-bar template SVG are integrated in the project. The 1024-pixel PNG remains in Downloads. The built retrace_app.icns and Assets.car contain retrace_app icon renditions.

## Local commits

1. 33cbc4c — Fail closed when redaction filters are unavailable
2. ee2b059 — Set retrace as the app name and icon
3. 0cc5ee2 — Mark inspector width as nonisolated
4. 7acc097 — Validate persisted settings before use
5. bfc59d3 — Reserve output paths before async writers start
6. cb60fb2 — Fail closed when image metadata cannot be verified
7. c7a5097 — Reject image metadata checks without readable properties

No commit was pushed or merged.

## Verified findings and completed work

### Redaction privacy

The reported blur/mosaic concern was confirmed: the preview could expose source pixels before a filter layer was ready, and export could skip a missing filter layer. Preview now paints an opaque temporary cover; export, copy, and save fail with a recovery message if a requested blur or mosaic layer is unavailable. Added pixel-level preview and export failure tests.

### Storage and export stability

- Concurrent recording/replay URL reservations could return the same path before either writer created a file. A process-wide, locked registry now reserves names and expires abandoned reservations after 24 hours.
- Metadata audit now throws if ImageIO cannot read the image source or its properties. Encoding and color/size preparation failures throw instead of silently returning the original image.
- Persisted settings are normalized against supported values before use, including finite image quality, frame rates, countdowns, replay lengths, size limits, and Quick Access close delays.
- Clipboard image work is invalidated when history is cleared, paused, or resumed; payload size, text length, and decoded dimensions are bounded.
- Video metadata stripping failure prevents copying or presenting the movie in Quick Access and leaves it in its save folder with a review warning.
- ScreenCaptureKit startup cancellation and stop/finalization have explicit state handling and a 60-second finalization bound. Deterministic lifecycle policy tests pass; real interactive start/stop is still outstanding.

### UI and code structure

- The main Library and Clipboard shell, toolbar capture/record controls, filters, grouped Settings forms, editor, and Quick Access use SwiftUI/AppKit controls and native materials. The Library no longer repeats its heading in its content area.
- The editor uses one native inspector material; no stacked or imitation glass surfaces were introduced. Zoom, palette editing, navigation, and inspector sizing use native controls.
- Xcode's accessibility tree for the running Library showed a native sidebar, filter menu, capture and record toolbar controls, search, and selectable capture items. Full VoiceOver and system text-size verification remain open.
- Screenshot encoding/storage and editor export/save work off the main UI path. Quick Access downsampling is cancellable and stale results are discarded. No speedup claim is made without an Instruments comparison.

## Verification

- Xcode MCP built the existing project successfully and reported no compiler warnings.
- All 36 XCTest tests passed (0 failures, 0 skips, 0 not run), including redaction, settings normalization, concurrent URL reservation, image metadata, clipboard, editor interaction, Library, storage, and Quick Access tests. The added test files currently remain untracked with the existing in-progress test-target setup.
- The built product includes retrace_app.icns (256 × 256) and retrace_app icon renditions in Assets.car.
- git diff --check passes.
- A standalone xcodebuild analyze attempt using a temporary DerivedData directory failed during actool processing because the CLI could not open the Icon Composer retrace_app.icon document. Xcode MCP build/test succeeds and the built product contains the icon; treat command-line static analysis as unverified, not as an app compiler warning.
- Live verification is read-only for the Library window. No capture, recording, permission grant, settings mutation, or user-file change was performed during the latest UI pass.

## Apple release and design guidance checked 2026-11-04

At the check date, macOS 27.2 was the latest stable release (released 2026-10-26); macOS 27.3 beta 1 was available (released 2026-11-03). The app targets macOS 26.0 and Xcode 27.2, so new APIs must be available at the deployment target and solve a concrete need. No novelty APIs or visual effects were added solely for appearance.

- [Apple Developer releases](https://developer.apple.com/news/releases/)
- [macOS release notes](https://developer.apple.com/documentation/macos-release-notes)
- [macOS 27.2 release notes](https://developer.apple.com/go/?id=macos-27_2-rn)
- [macOS 27.3 beta release notes](https://developer.apple.com/go/?id=macos-27_3-rn)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

## Remaining priorities

1. Continue reviewing and selectively committing the existing broad worktree without sweeping unrelated changes into commits.
2. Complete VoiceOver, keyboard navigation, minimum-window-size, larger system text, and light/dark appearance checks for Library, Settings, and editor.
3. Measure editor annotation rendering/save and capture-to-Quick-Access with representative Instruments traces before making performance claims.
4. Exercise clipboard pause/clear/exclusions/retention against real pasteboard changes and verify old image-file cleanup.
5. Exercise ScreenCaptureKit start, stop, cancellation, system stop, metadata stripping, and recovery in a permissioned session. Do not record user content without an explicit user-selected test target.
6. Review the remaining storage and settings work, then refresh the handoff and test suite after each coherent change.
7. Keep bundle identity, sandboxing, signing/distribution, and update policy unchanged until the user requests a distribution path.
