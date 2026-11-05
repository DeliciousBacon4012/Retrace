# Retrace Engineering Handoff

**Reviewed:** 2026-11-05
**Repository:** /Users/har/Documents/Developer/untitled-mac
**Branch:** feature/stability-and-performance
**Base:** origin/main at d902835
**Source checkpoint:** c630108

## Objective and working rules

Polish the existing macOS app into retrace while preserving its repository, project, user data, and working flows. Prefer native macOS controls and supported Apple APIs; keep materials restrained. Prioritize privacy, stability, accessibility, diagnosability, and measured performance. Never reset, discard, amend, rebase, squash, push, or merge history.

## Git and Xcode setup

- At source checkpoint c630108, the feature branch is 21 commits ahead of origin/main. This documentation refresh adds one docs-only commit, taking it to 22. The remote remains https://github.com/DeliciousBacon4012/untitled-mac.git. No push or merge occurred.
- Xcode uses the original Untitled.xcodeproj and My Mac. The active shared scheme is retrace. The shared Untitled scheme remains for compatibility. The app target is internally named Untitled and the hosted test target UntitledTests.
- The app product, executable, display name, icon, and active scheme use retrace. App version is 0.1.0 (build 1), category Productivity, minimum macOS 26.0, and Swift 6.0.
- Identity inventory: the project path, internal target/module names, test host, bundle identifier io.github.deliciousbacon4012.Untitled, Application Support domain, Pictures/Untitled folder, and Originals storage path remain unchanged. Those names participate in existing preferences, permissions, and user data. Existing Library filenames also remain untouched. The default filename template is retrace, but the user's saved Untitled template is preserved and currently appears in Settings; no user preference was reset.
- Signing is configured for Automatic signing with the existing Personal Team, Apple Development identity, and hardened runtime. No paid distribution certificate or entitlement was added. Xcode builds and launches locally, but this Mac has zero valid signing identities; the built app reports the team identifier and no available signing authority. It is not verified for distribution. App Sandbox remains off pending a distribution and file-access design.
- The existing /Users/har/Downloads/logos and icons/retrace_app.icon and retrace_menubar_template.svg are integrated. The 1024-pixel PNG remains at /Users/har/Downloads/logos and icons/retrace_icon_1024_app.png.
- Xcode's test-plan auto-creation is disabled on both shared schemes to prevent duplicate test discovery. The retrace scheme discovers the intended 42 tests.

## Source commits at c630108

1. 33cbc4c — Fail closed when redaction filters are unavailable
2. ee2b059 — Set retrace as the app name and icon
3. 0cc5ee2 — Mark inspector width as nonisolated
4. 7acc097 — Validate persisted settings before use
5. bfc59d3 — Reserve output paths before async writers start
6. cb60fb2 — Fail closed when image metadata cannot be verified
7. c7a5097 — Reject image metadata checks without readable properties
8. f1de190 — Update retrace engineering handoff
9. 2bfd289 — Harden recording and replay completion
10. 2443abc — Bound clipboard history work and payloads
11. 42b3d5a — Set up shared hosted Xcode tests
12. 02c52be — Keep image exports responsive and bounded
13. da2a83a — Cancel stale replay buffer startups
14. b39d6cc — Harden capture version recovery
15. bbc3ce2 — Add retrace Xcode scheme
16. 5001a94 — Add configurable capture destinations and library loading
17. 3533c83 — Refresh the native Library and Settings workflows
18. 49fcb7c — Improve editor interactions and save recovery
19. c10f70b — Harden ScreenCaptureKit recording finalization
20. 5e54f63 — Add clipboard and settings regression coverage
21. c630108 — Align internal diagnostics with retrace

## Verified findings and completed work

### Privacy, storage, and reliability

- Confirmed and fixed the reported blur/mosaic concern. Preview uses an opaque cover until the redaction layer is ready; export, copy, and save fail closed when a requested filter layer is missing.
- Image metadata audits now reject unreadable image sources or properties. Encoding and color/size preparation failures return recoverable errors instead of silently saving the original.
- Recording and replay paths are reserved before asynchronous writers start. The locked registry prevents concurrent name collisions and expires abandoned reservations after 24 hours.
- Persisted values are normalized before use. Clipboard image conversions are invalidated after clear/pause changes, and image/text payload sizes are bounded. New/defaulted installs retain clipboard entries for 30 days while existing explicit choices are preserved.
- Video metadata stripping failure prevents copying or showing the movie in Quick Access and leaves the recording in its save folder with a recovery message.
- Recording startup, stop, stream callbacks, output completion, file validation, and a 60-second finalization timeout have explicit state handling. Deterministic lifecycle tests pass; live ScreenCaptureKit start/stop has not yet been exercised.
- Capture versions validate index paths and file types and recover safely when the source or index write fails. Restore failures preserve edited files.

### App structure and UI

- Added multiple configured Library folders, per-session capture destination selection, a default destination, path normalization, and non-destructive removal. Existing files are never moved or deleted when a location is removed.
- Library and Clipboard cards share aligned 3:2 previews. The Library supports combined folder results, search/filtering, Finder-style selection, keyboard navigation, Quick Look, and accessibility actions.
- Settings use the macOS split-view sidebar and grouped forms. Capture destinations, clipboard retention/privacy, and Quick Access sizing/aspect ratio are exposed through native controls.
- The editor has a responsive inspector, saved custom color palette, multi-selection movement and undo safety, annotation accessibility actions, and background encoding/file writes. Save-in-progress state prevents editing or closing a document before its render is consistent.
- Quick Access thumbnails downsample off the UI path. Cancellable tasks discard stale results after a card closes or its size changes.
- Library and Settings were visually reviewed in the Xcode-launched app on 2026-11-05. The live accessibility tree exposed the sidebar, filter, capture/record controls, search, selectable items, native settings categories, and controls. No capture, recording, permission grant, settings change, or user-file operation was performed during this pass.
- The custom inspector has one native glass surface; standard controls use system styling. No imitation glass layers were added. Performance gains are not claimed without Instruments data.

### Runtime diagnostics

- A negative-frame-size breakpoint was traced to AppKit's NSThemeFrame window-sharing session recipient indicator. Its stack stayed within AppKit and did not enter app code. No speculative size clamp was added.
- A standalone xcodebuild Analyze attempt still fails in actool while opening the Icon Composer document. This is not a compiler warning; static analysis remains unverified.

## Verification at source checkpoint

- Xcode MCP built and launched the existing project using the retrace scheme on My Mac.
- All 42 XCTest tests passed: 0 failures, 0 skips, 0 expected failures, and 0 not run.
- Xcode's latest warning query returned zero build warnings.
- Build settings report PRODUCT_NAME and CFBundleDisplayName as retrace, MARKETING_VERSION 0.1.0, CURRENT_PROJECT_VERSION 1, MACOSX_DEPLOYMENT_TARGET 26.0, Swift 6.0, automatic signing, and hardened runtime enabled.
- The local app bundle signature contains TeamIdentifier ZX34GARNUS, but codesign reports no available Authority and security reports zero valid identities. Local run succeeds; distribution signing is not established.
- The built product contains retrace_app icon renditions and retrace_app.icns.
- git diff --check passed before this documentation refresh.

## Apple releases and design guidance checked 2026-11-05

At the check date, macOS 27.2 (26B123, released 2026-10-26) was the latest stable macOS release. macOS 27.3 beta (26C5035r, released 2026-11-03) is a beta and is not treated as stable. Xcode 27.2 is installed; Xcode 27.3 beta is available. The project targets macOS 26.0 and remains built against the stable toolchain. APIs are adopted only when they solve a real need and are available at the deployment target.

- [Apple Developer releases](https://developer.apple.com/news/releases/)
- [macOS 27.2 stable release](https://developer.apple.com/news/releases/?id=10262026d)
- [macOS 27.3 beta release](https://developer.apple.com/news/releases/?id=11032026c)
- [macOS release notes](https://developer.apple.com/documentation/macos-release-notes)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Materials Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

Apple's macOS guidance emphasizes flexible windows, keyboard and precise pointer input, useful information density, and personalization. Standard controls already adopt the current system materials; custom material effects should stay limited to places where they communicate an actual floating or interactive surface.

## Remaining priorities

1. Finish VoiceOver, keyboard-only, minimum live window size, larger system text, and light/dark appearance checks across Library, Settings, and editor.
2. Exercise ScreenCaptureKit start/stop/cancellation/system-stop/finalization in a permissioned session. Use only a user-selected test target; do not capture user content.
3. Exercise clipboard pause/clear/exclusion/retention against real pasteboard changes and verify expiry cleanup. Source-app exclusions remain best-effort because macOS does not expose reliable pasteboard provenance to this watcher.
4. Capture representative Instruments traces for annotation rendering/save and capture-to-Quick-Access before making performance claims.
5. Revisit static analysis through a workflow that handles the Icon Composer asset, then record the analyzer result.
6. Decide on distribution before changing bundle identity, sandboxing, signing, notarization, or update delivery. The current local signing setup is sufficient for this user's Xcode development workflow but is not distribution-ready.
