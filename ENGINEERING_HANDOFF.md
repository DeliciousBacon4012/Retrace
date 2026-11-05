# Retrace Engineering Handoff

**Reviewed:** 2026-11-05
**Repository:** /Users/har/Documents/Developer/untitled-mac
**Branch:** feature/stability-and-performance
**Base:** origin/main at d902835
**Source checkpoint:** 82b1978

## Objective and working rules

Polish the existing macOS app into retrace while preserving its repository, project, user data, and working flows. Prefer native macOS controls and supported Apple APIs; keep materials restrained. Prioritize privacy, stability, accessibility, diagnosability, and measured performance. Never reset, discard, amend, rebase, squash, push, or merge history.

## Git and Xcode setup

- At source checkpoint 82b1978, the feature branch is 37 commits ahead of origin/main. This documentation refresh is a separate docs-only commit, taking it to 38. The remote remains https://github.com/DeliciousBacon4012/untitled-mac.git. No push or merge occurred.
- Xcode uses the original Untitled.xcodeproj and My Mac. The active shared scheme is retrace. The shared Untitled scheme remains for compatibility. The app target is internally named Untitled and the hosted test target UntitledTests.
- The app product, executable, display name, icon, and active scheme use retrace. App version is 0.1.0 (build 1), category Productivity, minimum macOS 26.0, and Swift 6.0.
- Identity inventory: the project path, internal target/module names, test host, bundle identifier io.github.deliciousbacon4012.Untitled, Application Support domain, Pictures/Untitled folder, and Originals storage path remain unchanged. Those names participate in existing preferences, permissions, and user data. Existing Library filenames also remain untouched. The default filename template is retrace, but the user's saved Untitled template is preserved and currently appears in Settings; no user preference was reset.
- Signing settings use Automatic signing, team ZX34GARNUS, Apple Development identity, and hardened runtime. No paid Developer ID certificate or distribution entitlement was added. Xcode builds and launches locally, but `security find-identity -v -p codesigning` reports zero valid identities and strict `codesign --verify --deep --strict` returns `CSSMERR_TP_NOT_TRUSTED`. This is usable for the current local Xcode workflow, not verified for distribution. App Sandbox remains off pending a distribution and file-access design.
- The existing /Users/har/Downloads/logos and icons/retrace_app.icon and retrace_menubar_template.svg are integrated. The 1024-pixel PNG remains at /Users/har/Downloads/logos and icons/retrace_icon_1024_app.png.
- Xcode's test-plan auto-creation is disabled on both shared schemes to prevent duplicate test discovery. The retrace scheme discovers 59 tests.

## Source commits through c630108

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

## Commits since c630108

22. 26d9b60 — Update retrace engineering handoff and roadmap
23. e1d45c0 — Fix capture crash from invalid window IDs
24. 95978c6 — Add unified Library Editor and Settings navigation
25. b05c71d — Add capped replay buffer menu timer
26. a2137e8 — Update engineering handoff after capture and UI fixes
27. fd1a75e — Add Vision person redaction and smart crop
28. b34fdcc — Document Vision redaction and smart crop
29. e184e27 — Add foreground subject copy with Vision
30. 41859bc — Document foreground subject copy checkpoint
31. a177c3b — Verify Vision OCR on readable image data
32. c0671d1 — Add native editor drag exports
33. f8c523d — Add OCR text formatting preference
34. 82b1978 — Unify navigation around native glass toolbars

## Verified findings and completed work

### Privacy, storage, and reliability

- Confirmed and fixed the reported blur/mosaic concern. Preview uses an opaque cover until the redaction layer is ready; export, copy, and save fail closed when a requested filter layer is missing.
- Image metadata audits now reject unreadable image sources or properties. Encoding and color/size preparation failures return recoverable errors instead of silently saving the original.
- Recording and replay paths are reserved before asynchronous writers start. The locked registry prevents concurrent name collisions and expires abandoned reservations after 24 hours.
- Persisted values are normalized before use. Clipboard image conversions are invalidated after clear/pause changes, and image/text payload sizes are bounded. New/defaulted installs retain clipboard entries for 30 days while existing explicit choices are preserved.
- Video metadata stripping failure prevents copying or showing the movie in Quick Access and leaves the recording in its save folder with a recovery message.
- Recording startup, stop, stream callbacks, output completion, file validation, and a 60-second finalization timeout have explicit state handling. Deterministic lifecycle tests pass; one short live area movie was recorded, while the broader start/stop/cancel/system-stop/finalization matrix remains unverified.
- Fixed the immediate freeze/crash when excluding the app's own floating capture windows. AppKit can return window number `4294967296`, outside `CGWindowID`'s 32-bit range; direct conversion trapped. Window IDs now use a checked conversion that rejects null and out-of-range values. A regression test covers the boundary.
- Live verification through Xcode MCP successfully captured a selected screen area as a PNG and made a short area recording as a MOV: `/Users/har/Pictures/Untitled/Untitled 2026-11-05 at 01.47.58.png` and `/Users/har/Pictures/Untitled/Untitled 2026-11-05 at 02.00.38.mov`. These checks confirm the reported capture path no longer crashes; they do not cover all display/window modes, audio, cancellation, long recordings, or replay-buffer finalization.
- Capture versions validate index paths and file types and recover safely when the source or index write fails. Restore failures preserve edited files.

### App structure and UI

- Added multiple configured Library folders, per-session capture destination selection, a default destination, path normalization, and non-destructive removal. Existing files are never moved or deleted when a location is removed.
- Library and Clipboard cards share aligned 3:2 previews. The Library supports combined folder results, search/filtering, Finder-style selection, keyboard navigation, Quick Look, and accessibility actions.
- The main window is the Library. A native segmented toolbar picker switches between Library and Clipboard; capture and recording remain direct toolbar actions. The extra Capture/Library/Settings workspace picker and the hand-drawn material background were removed. The app's standard Settings command opens the separate macOS Settings scene.
- Settings categories now use a centered native segmented picker in the Settings toolbar rather than a left dashboard/sidebar. Preference content uses centered, scrollable macOS Forms without grouped glass-card backgrounds. System switches and buttons retain their native styles.
- Opening a Library item launches the existing document editor. The main Library view's image drop handler routes dropped images to that editor; external image dropping was not exercised live. The empty Editor landing page was removed with the redundant Editor tab; no editor canvas or capture workflow was replaced.
- The Editor's custom tool palette uses `.glassEffect(.regular.interactive(), in: .capsule)`. Standard toolbar pickers rely on the operating system's Liquid Glass treatment, without custom material backplates. This follows Apple's guidance to use standard toolbars and controls and reserve custom Liquid Glass for purposeful custom controls.
- Replay-buffer menu status keeps the retrace logo visible with a separate red dot and timer. The display counts up and caps at the configured duration; after the cap, the dot pulses while recording continues and old footage rotates out. Three deterministic tests cover capping/pulse behavior and normal recording time.
- The editor can detect faces, people, personal text, or all text on device; results become individual editable redaction marks. The Crop inspector also offers an attention-saliency Smart Crop suggestion with progress/error feedback. Suggestions remain adjustable before the person applies them.
- The Select inspector offers Copy Subject using `VNGenerateForegroundInstanceMaskRequest` and Core Image mask compositing. The action works on a fully rendered copy, preserving existing redactions, then writes a transparent image to the clipboard without replacing the source. Images are size-bounded and Vision has a timeout. The mask compositor's alpha behavior is covered with a synthetic image; positive subject detection and edge quality on real photographs still need verification.
- The Select inspector offers native Core Transferable sources for the fully rendered PNG and the most recent OCR text. Image rendering starts only when dragging begins; PNG encoding is deferred to the transfer representation. The rendered path includes redaction filters. The PNG encoder is verified by decoding a generated PNG and checking its type and dimensions; a missing-image error is also covered. Live inspection confirms the image drag control appears in the Select inspector. Cross-app drops and the OCR text drag after a live OCR result remain to be exercised.
- OCR copy now uses one shared formatter for area Text Capture and Editor OCR. A persisted Editor setting keeps Vision's line breaks by default or joins recognized lines into one paragraph; blank lines are removed, whitespace-only results are treated as empty, and detected codes remain a fallback if no usable text line exists. OCR remains on-device and automatic clipboard copying is disclosed in Settings. The Settings control and accessibility label were inspected live; pasteboard contents and both formatting choices still need an end-to-end capture check.
- The editor has a responsive inspector, saved custom color palette, multi-selection movement and undo safety, annotation accessibility actions, and background encoding/file writes. Save-in-progress state prevents editing or closing a document before its render is consistent.
- Quick Access thumbnails downsample off the UI path. Cancellable tasks discard stale results after a card closes or its size changes.
- Library, Settings, and the Editor were visually reviewed in the Xcode-launched app on 2026-11-05. The Library showed only its Library/Clipboard segmented toolbar control plus capture and record actions; Settings showed its toolbar category picker and centered form without a sidebar; the Editor's existing image document showed its editing tool row. Existing Library-to-Editor opening was exercised. Capture/record actions were exercised separately as listed above.
- The custom inspector has one native glass surface; standard controls use system styling. No imitation glass layers were added. Performance gains are not claimed without Instruments data.

### Runtime diagnostics

- A negative-frame-size breakpoint was traced to AppKit's NSThemeFrame window-sharing session recipient indicator. Its stack stayed within AppKit and did not enter app code. No speculative size clamp was added.
- A standalone xcodebuild Analyze attempt still fails in actool while opening the Icon Composer document. This is not a compiler warning; static analysis remains unverified.

## Verification at source checkpoint 82b1978

- Xcode MCP built the existing project and ran all tests using the retrace scheme on My Mac. The app launched successfully after the navigation/UI changes. Live inspection confirmed the Library and Settings segmented toolbar controls, the absence of the Settings sidebar and extra workspace tabs, and the Editor's existing image tool row. Live inspection of the Select tool showed `Copy or Drag Image`; the text action appears only after OCR succeeds. Live Settings inspection showed `Keep line breaks in copied text` enabled with its on-device/clipboard disclosure.
- All 59 XCTest tests passed on 2026-11-05: 0 failures, 0 skips, 0 expected failures, and 0 not run. New transfer tests confirm that an image encodes as a readable PNG with the source dimensions and that an unavailable image produces a recoverable error. OCR formatting tests cover line preservation, paragraph joining, codes, whitespace-only output, and the codes fallback; malformed persisted values fall back to the enabled default. Cross-app drag delivery, text dragging after live OCR, and live OCR clipboard output under both Settings choices were not exercised. A generated high-contrast sample confirms Vision returns readable OCR text despite the system E5 log messages. Coverage also includes Smart Crop bounds/undo, blank-image Vision behavior, and alpha composition for a generated subject mask; it does not verify detector accuracy or mask edge quality on real photographs.
- The latest Xcode build succeeded and the warning query returned zero warnings or Swift compiler errors. A prior build logged a benign App Intents metadata-extraction warning because the app does not declare `AppIntents.framework`; it did not recur in the latest warning query.
- All 59 existing tests passed after the UI changes; no new test was added for view composition. `git diff --check` passed. The UI change did not alter the existing Xcode project settings or target/scheme structure.
- Build settings report PRODUCT_NAME and CFBundleDisplayName as retrace, MARKETING_VERSION 0.1.0, CURRENT_PROJECT_VERSION 1, MACOSX_DEPLOYMENT_TARGET 26.0, Swift 6.0, automatic signing, and hardened runtime enabled.
- The local app bundle reports team identifier ZX34GARNUS, but strict signature verification returns `CSSMERR_TP_NOT_TRUSTED` and security reports zero valid identities. Local Xcode launch succeeds; distribution signing is not established.
- The built product contains retrace_app icon renditions and retrace_app.icns.
- git diff --check passed before this documentation refresh.

### API and capability inventory

- In use: ScreenCaptureKit; `SCRecordingOutput`; AVAssetWriter for replay output; Vision OCR, barcode, face and human rectangle detection, attention saliency, and foreground-instance masks; Core Image Gaussian blur, pixellation, and foreground-mask compositing; CGWindowList window discovery; Carbon `RegisterEventHotKey`; UTType; on-device OCR with configurable line formatting and clipboard copy; and Core Transferable exports for rendered PNG images and recognized text. Recognition runs on a bounded worker queue. People redaction and Smart Crop have synthetic-image and crop geometry coverage; the subject-mask compositor has synthetic alpha coverage. Accurate detections and edge quality on real photos still need a user-selected verification sample.
- Not implemented: AXUIElement-based control snapping; Share or Finder Sync extensions; explicit VideoToolbox codec/ProRes preference UI; recording click/keystroke overlays or cursor motion blur; and user-defined post-capture scripts.
- Treat those as candidates, not promised architecture. Human/face privacy tools require clear preview/confirmation and safe fallbacks. Accessibility snapping requires a permission and should remain optional. Share/Finder extensions add targets, signing, review, and lifecycle work. Running arbitrary user scripts adds a substantial security boundary. Adopt APIs only for a user-facing need that fits macOS 26.0.

### OCR runtime note

- The latest Xcode launch again logged three `[e5rt]` errors from Apple's private TextRecognition runtime about missing E5 model bundles (text detection, orientation, and Latin/Cyrillic recognition). The app launched; no app crash stack was present, and the Xcode build warning query returned zero warnings. A positive synthetic OCR integration check passed, so the messages do not currently show a broken OCR path. Keep monitoring and verify against a real capture before treating the system logs as harmless.

## Apple releases and design guidance checked 2026-11-05

At the check date, macOS 27.2 (26B123, released 2026-10-26) was the latest stable macOS release. macOS 27.3 beta (26C5035r, released 2026-11-03) is a beta and is not treated as stable. Xcode 27.2 is installed; Xcode 27.3 beta is available. The project targets macOS 26.0 and remains built against the stable toolchain. APIs are adopted only when they solve a real need and are available at the deployment target.

- [Apple Developer releases](https://developer.apple.com/news/releases/)
- [macOS 27.2 stable release](https://developer.apple.com/news/releases/?id=10262026d)
- [macOS 27.3 beta release](https://developer.apple.com/news/releases/?id=11032026c)
- [macOS release notes](https://developer.apple.com/documentation/macos-release-notes)
- [WWDC25: Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Materials Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Vision foreground instance-mask request](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest)
- [VNInstanceMaskObservation instances](https://developer.apple.com/documentation/vision/vninstancemaskobservation/allinstances)
- [Generating a scaled Vision mask](https://developer.apple.com/documentation/vision/vninstancemaskobservation/generatescaledmaskforimage%28forinstances%3Afrom%3A%29)

Apple's macOS guidance emphasizes flexible windows, keyboard and precise pointer input, useful information density, and personalization. Standard controls already adopt the current system materials; custom material effects should stay limited to places where they communicate an actual floating or interactive surface.

## Remaining priorities

1. Expand live capture verification: display/window/area, cancellation, permission denial, audio choices, system stop, longer recording, and replay save/finalization. Use a user-selected test target.
2. Verify Smart Crop, person redaction, and Copy Subject on a user-selected image; inspect mask edges and transparent pasteboard output; check face/text redaction and follow up on system TextRecognition/Espresso model logs if OCR fails. Detector results remain suggestions that users can review and adjust.
3. Exercise VoiceOver and keyboard-only navigation, minimum window sizes, larger system text, and light/dark appearance in Library, Settings, and Editor. Live-test dropping an image from Finder onto the main window. Test live OCR copy with line breaks both enabled and disabled, then verify real pasteboard changes and expiry cleanup; source-app exclusions remain best-effort because macOS does not expose reliable pasteboard provenance to this watcher.
4. Capture representative Instruments traces for annotation rendering/save and capture-to-Quick-Access before making performance claims; revisit static analysis through a workflow that handles the Icon Composer asset.
5. Verify image and OCR text drag delivery to another app, then stage remaining APIs by user need: defer AX snapping until its permission model is justified; evaluate Share/Finder extensions and explicit codec controls only after target/signing/distribution design. Do not execute arbitrary scripts without a reviewed security model.
6. Decide on distribution before changing bundle identity, sandboxing, signing, notarization, or update delivery. Current Xcode settings support local build/launch only; strict trust verification and a valid signing identity are absent.
