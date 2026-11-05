# Retrace Engineering Roadmap

## Current checkpoint — 2026-11-05

- Branch: feature/stability-and-performance
- Baseline commit: `d9028354c0bc0b9a9267ead9f6f136c0519d2ae0`
- Source checkpoint: fd1a75e, 27 commits ahead of origin/main. This handoff/roadmap refresh is a docs-only commit, taking the branch to 28. No push or merge occurred; origin remains https://github.com/DeliciousBacon4012/untitled-mac.git.
- Source and test changes are committed. The existing Untitled.xcodeproj, Untitled application target, UntitledTests hosted test target, active shared retrace scheme, and compatibility shared Untitled scheme remain in use. Product is retrace.app, version 0.1.0 (build 1), minimum macOS 26.0.
- Xcode MCP built and launched on My Mac. All 50 tests passed. The latest build and warning query reported no warnings or Swift compiler errors. A prior build emitted an App Intents metadata-extraction warning because the app does not link `AppIntents.framework`; it did not recur. `git diff --check` passed before this documentation refresh. The app bundle contains retrace_app icons.
- Automatic signing is configured for local development with team ZX34GARNUS and hardened runtime. This Mac has zero valid signing identities, and strict `codesign` verification returns `CSSMERR_TP_NOT_TRUSTED`. The built app launches locally but is not verified for distribution. App Sandbox remains disabled pending a distribution decision.
- The original bundle/module/target and data paths remain for continuity. See ENGINEERING_HANDOFF.md for the full impact inventory and signing evidence.
- On 2026-11-05, Apple lists macOS 27.2 as latest stable and macOS 27.3 as beta; the app stays on its macOS 26.0 deployment target and stable Xcode 27.2 toolchain.
- The main window now has Library/Editor/Settings navigation. Library, empty Editor, and Settings were reviewed live; the Settings sidebar has no redundant toggle. An area screenshot and short area movie were created successfully after fixing the crash caused by an out-of-range AppKit window number. This verifies the reported area-capture failure only, not all recording modes or audio.
- Replay buffer menu time is capped at its configured duration and its red indicator pulses at the cap while recording continues. The retrace menu-bar logo remains visible.
- The Editor drop zone accepts image URLs and opens them in the existing editor. Vision now includes human rectangle redaction and attention-based Smart Crop in addition to the existing face/text redaction. Manual review, crop adjustment, and undo are retained. Synthetic-image tests pass; real-photo detector accuracy remains to be verified.
- The source wishlist is inventoried in ENGINEERING_HANDOFF.md. Existing Vision face/person/OCR/saliency, Core Image redaction, Carbon hotkeys, ScreenCaptureKit, UTType, and OCR clipboard paths are distinguished from future foreground masks, accessibility snapping, CoreTransferable, Share/Finder extensions, codec preferences, cursor effects, and scripting. No novelty API or beta-only API was added.
- Older dated entries below are historical checkpoints. The handoff contains the current verification evidence and prioritized remaining work.

## Earlier completed work logged 2026-11-04

### Practical XCTest foundation

- Added a macOS-only XCTest bundle hosted by the existing `Untitled` app target and retained the existing `Untitled` scheme.
- Added deterministic recording startup/output-policy tests, clipboard generation/bounds tests, feature-tier invariant coverage, storage collision/data-integrity coverage, and capture-version preservation/failure tests (12 total).
- Matched the test bundle's development team to the hosted app so XCTest can load it on this Mac.
- Build: app and test bundle succeeded on 2026-11-04.
- Tests: 12 passed, 0 failed on 2026-11-04. ScreenCaptureKit's live start/stop/finalization still requires an interactive runtime check.

### Screenshot save responsiveness

- Screenshot encoding now uses the existing background ImageIO encoder.
- Capture storage is an actor, so screenshot data writes and output URL preparation are awaited away from the main actor; Quick Access's deferred save follows the same async path.
- Recording and replay output URL reservation now await the storage actor.
- Tests: storage coverage confirms byte preservation and collision suffix behavior. A short 5.8-second idle Time Profiler trace was captured, but its export exposed schemas rather than useful per-operation samples; no interaction latency baseline or before/after performance claim is available.

### Editor save and export responsiveness

- Editor image rendering remains on the UI actor, but encoding, metadata audit, and atomic file writes now run through background ImageIO/file operations.
- The editor communicates save progress and prevents editing or closing while a save is in flight, so the saved render stays consistent with the document state. Save failures leave the window open and remain visible.
- Export uses the same background encode/write path, snapshots export options at confirmation, and shows progress while controls are disabled.
- Build: app and test bundle succeeded on 2026-11-04. Tests: 12 passed, 0 failed.

### Original version preservation responsiveness and integrity

- The first untouched-image copy now runs on a background executor before an edited save replaces the source file.
- Copy or index-write failure keeps the existing source intact and reports a recoverable save error. An index-write failure rolls back the in-memory entry and removes the unindexed copy where possible.
- Added tests for preserving the original across an edit and for refusing the save when the originals index cannot be written.
- Build: app and test bundle succeeded on 2026-11-04. Tests: 12 passed, 0 failed.

### Feature accuracy and editor accessibility

- Promoted verified shipped features into the available/core tier, corrected clipboard history wording, and removed the unsupported PDF claim from the format roadmap.
- Annotation layers now appear individually in the accessibility tree with selection state and Select/Delete actions; draft layers remain hidden.
- Build: app and test bundle succeeded on 2026-11-04. Tests: 12 passed, 0 failed, including available-feature tier and clipboard-retention default, persistence, and reset checks. VoiceOver runtime verification remains outstanding.

### Clipboard privacy defaults and disclosure

- Fresh/defaulted installs now retain clipboard items for 30 days; a stored user choice such as Forever is preserved. Reset to Defaults returns to 30 days.
- Clipboard Settings now explains that private pasteboard markers are honored and source-app exclusions depend on the frontmost app observed at detection time.
- Added an isolated UserDefaults test for the 30-day default and persistence of an explicit Forever choice.
- Build: app and test bundle succeeded on 2026-11-04. Tests: 12 passed, 0 failed.

### Video metadata privacy gate

- Metadata removal now throws when inspection or rewriting fails, including when metadata remains after the rewrite.
- Recording and replay flows show the failure and keep the file in its save folder, but do not copy it or present it in Quick Access when the strip-metadata setting is on.
- Build: app and test bundle succeeded on 2026-11-04. Tests: 12 passed, 0 failed. A metadata-bearing movie fixture has not yet been exercised end-to-end.

### Recording lifecycle stabilization

- Stop requests during startup are recorded; startup is cancelled before `startCapture()`, or stopped immediately after an in-flight start returns.
- Movie completion waits for `SCRecordingOutputDelegate` and stream-stop completion, validates nonempty output, and uses a 60-second failure-only timeout.
- Startup cancellation does not show a generic error.
- Build: Xcode scheme `Untitled` succeeded on 2026-11-04.
- Tests: deterministic start/stop/output-policy coverage is included; live ScreenCaptureKit lifecycle behavior remains unverified.

### Clipboard data safety

- Clear and clipboard-history setting changes invalidate pending image conversions; stale conversions discard their generated PNG rather than restoring a cleared entry.
- Clipboard images are checked for a maximum 16,384-pixel edge and 40-million-pixel total before full decode. Failed PNG writes clean up partial output.
- Build: Xcode scheme `Untitled` succeeded on 2026-11-04.
- Tests: deterministic generation invalidation and image-bound tests pass; actual pasteboard conversion races have not been exercised end-to-end.

## Historical priorities before 2026-11-05

1. Capture representative editor/save and capture/Quick Access traces in Instruments so remaining rendering and interaction work can be prioritized from measured costs.
2. Review custom controls with VoiceOver and keyboard navigation; verify annotation layer actions in a live accessibility session.
3. Verify clipboard file cleanup and source-app exclusion behavior under real pasteboard changes; the 30-day default is implemented, but exclusions cannot guarantee clipboard provenance.
4. Decide distribution (Mac App Store, direct, or both), then assess sandboxing, signing, notarization, update delivery, and data migration. Do not implement an updater until distribution is decided.

## Historical risks recorded before the latest capture and UI verification

- Forty-two deterministic tests covered redaction, storage, Library, clipboard, editor interactions, metadata, and recording policies at that earlier checkpoint. The current count is 50; area screenshot and short area movie capture have since been verified, while the broader lifecycle matrix remains open.
- If ScreenCaptureKit never completes `stopCapture()`, the recorder times out and recovers to idle; a partial file may remain if the stream never releases it.
- Clipboard exclusions use the frontmost app observed by a polling watcher and cannot guarantee source-app provenance.
- Clipboard history remains enabled by default; new/defaulted settings expire items after 30 days, while any stored user choice is preserved. Source-app exclusions remain best-effort because macOS does not expose reliable pasteboard provenance to this watcher.
- Annotation rendering and small originals-index JSON persistence still run synchronously. Representative interaction latency and energy baselines remain uncollected.
- Video metadata stripping now blocks copy/Quick Access on failure, but this failure path has no movie-fixture integration test yet.
- Annotation accessibility and feature status have code-level support and invariant tests, but still need live VoiceOver verification. Other custom controls need review.
- App Sandbox is disabled. No trusted signing identity is present and distribution intent is not established.

## Historical design notes from 2026-11-04

Phase 1 — Product shell and visual design. The main window has a native Library/Clipboard sidebar, a focused content area, standard Capture/Record toolbar actions, and a compact native filter menu. Settings use the standard split view and sidebar. The editor inspector is one Glass panel with standard Form controls; avoid nested card backgrounds and manually applied Glass effects on controls that already have native styling.

### Product shell and design foundation

- Reworked the main window information architecture around the two durable destinations: Library and Clipboard. Capture and Record remain immediate actions in the unified macOS toolbar.
- The Library filter currently uses one compact SwiftUI `Menu` beside the heading, styled with `.buttonStyle(.glass)`. The menu is system-tracked and exposes its current choice in accessibility; there is no custom segmented bar or extra Glass overlay.
- Replaced the custom settings drag selector with a native `NavigationSplitView`, `List(selection:)`, and grouped `Form`; the last-selected pane remains persisted.
- Moved save location, naming, format, and metadata controls from General into Capture settings. Kept Quick Look behavior with the Library preferences, kept clipboard retention and clear-history with Clipboard settings, and kept the save-folder action next to its location setting.
- Removed a conditional toolbar “More” menu that did not appear in the running app. Its existing actions remain available through the focused settings panes.
- Reduced the main window minimum to 800 × 520 points while retaining the 1,180 × 760 default. At the minimum preview size, the sidebar and all four filters fit, Capture and Record remain visible, and macOS collapses Search to its native toolbar icon. The filter sits in the content header so primary toolbar actions retain room at narrow widths.
- Earlier live checks exercised the pre-redesign app's Library at default, zoomed, and half-screen widths and changed its sidebar selection with arrow keys. Those checks do not verify the redesigned MainView.
- General, Capture, and Clipboard settings were previously checked in the running app and now use a native split-view sidebar and grouped forms. VoiceOver verification remains open.
- Replaced the editor's always-visible slider with a compact directly draggable zoom percentage. Clicking reveals a native logarithmic Slider popover with Fit and 100% actions; SwiftUI's numeric text transition provides the rolling digit change. Direct drag was verified live from 100% to 115%.
- The Library filter was moved out of the toolbar after the 800 × 520 preview showed toolbar overflow. Its current compact native Menu sits beside the Library heading; Capture and Record remain in the toolbar and Search adapts to its native icon.
- Added debug-only Library previews with eight generated sample screenshots stored under the system temporary directory. At 800 × 520, the adaptive grid shows three columns; at 1,180 × 760, it shows five. The sample-named images load directly in Xcode previews because Quick Look thumbnails do not resolve in static previews; release builds continue to use Quick Look unchanged.
- Set the Library grid's adaptive minimum to 160 points and removed truncated file-size text from the visible caption. The complete date and file size remain available as native help text.
- Build: Xcode scheme `Untitled` and test bundle succeeded on 2026-11-04. Tests: 12 passed, 0 failed. Light previews at 800 × 520 and 1,180 × 760 and a dark 800 × 520 preview were visually inspected.
- Runtime check: Xcode launched the correct DerivedData build (PID 82374), but the main scene is suppressed on launch. The UI inspection tool attached to a separate older installed Untitled instance, so the redesigned MainView still needs a live runtime check.
- Build: Xcode scheme `Untitled` succeeded on 2026-11-04. Tests: 12 passed, 0 failed. In the running editor, accessibility adjustment moved the zoom to 200%, then native menu selections returned it to 100% and Fit. Reduce Transparency was enabled for a legibility check and restored to its original setting afterward.
- The older live Library surface was inspected in a half-screen native window tile at about 900 points wide; this does not verify the redesigned MainView. The populated 800 × 520 layout is now checked in Xcode Preview, while live MainView and VoiceOver checks remain open.
- Build: Xcode scheme `Untitled` succeeded on 2026-11-04. Tests: 12 passed, 0 failed. App launch succeeded. The manual ScreenCaptureKit lifecycle still needs a real permissioned runtime session.
- Thumbnail rendering now requests at most 320 × 118 points, matching the largest Library/Clipboard card image area, instead of 320 × 220. `aspectRatio(.fit)` preserves each capture's source proportions. A changed URL/version clears the previous image, and a cancelled request cannot paint a stale result. Thumbnail arrival is immediate with no decorative fade. The request-size change should reduce decoded/cache pixels for typical screenshots; the exact savings depend on source aspect ratio and display scale and have not yet been profiled.
- Quick Access floors now expand/collapse together on the existing spring instead of adding an index-based delay. The floating panel closes from SwiftUI's animation completion (`.removed`), guarded so a capture arriving mid-dismiss keeps it visible; the fixed 300 ms sleep is gone. Apple's [AnimationCompletionCriteria](https://developer.apple.com/documentation/swiftui/animationcompletioncriteria) documents this completion behavior.
- Build: Xcode scheme `Untitled` succeeded on 2026-11-04 with no warnings. Tests: 12 passed, 0 failed. The populated 800 × 520 preview was re-rendered on macOS 27.0.1; landscape and portrait sample images remain aspect-fit in aligned cards. Xcode launched the current build (PID 84003), but UI automation timed out while binding to that exact app bundle, so live MainView and Quick Access interaction remain unverified.
- Apple guidance consulted: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/), [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass), SwiftUI [`glassEffect`](https://developer.apple.com/documentation/swiftui/view/glasseffect%28_%3Ain%3A%29), and Apple's [macOS Liquid Glass toolbar walkthrough](https://developer.apple.com/videos/play/wwdc2025/310/). Apple's current guidance reserves Liquid Glass for the functional navigation/control layer, avoids glass in content surfaces, and recommends standard controls so the system provides its current appearance and behavior.

### Native UI cleanup — 2026-11-04

- Replaced the custom segment drawing in the editor's segmented choices with SwiftUI's native segmented `Picker`. Removed the extra `.glassEffect` wrapper and hid the duplicate visual picker label; selection, keyboard behavior, and accessibility now come from the platform control.
- Changed the editor inspector's nested grouped `Form` to the automatic macOS Form style. The inspector remains one glass panel; its settings no longer stack several additional rounded cards inside it.
- Made the zoom percentage a native `.buttonStyle(.glass)` control. Click opens the native slider popover; a simultaneous drag gesture updates zoom directly, Option slows the scrub, scroll zoom still works, and the number uses SwiftUI's numeric text transition. Live verification: click opened the popover and drag moved 100% to 115%.
- Removed rounded quaternary tiles behind Library thumbnails and text previews, and removed the extra “original behind edited” decoration. The grid retains its adaptive layout, fixed thumbnail region, source aspect fit, metadata, selection outline, and edited-version action.
- Removed the gradient from debug sample artwork. No gradient is used to style the app UI.
- Live inspection: the Library and settings sidebar were checked in the running app; the editor's segmented controls, inspector, zoom popover, and direct zoom drag were checked in the running app.
- Build: Xcode scheme `Untitled` succeeded on 2026-11-04 without reported errors or warnings. Tests: 12 passed, 0 failed. Xcode launched the updated app successfully.

## Historical next work from 2026-11-04

1. Continue refining the shell against default and minimum window sizes; verify settings pane balance and keyboard/VoiceOver navigation live.
2. Complete the Library workflow through selection, Quick Look, context menus, drag, and capture-to-editor handoff without adding visual layers back.
3. Rework the editor workflow next: selection and annotation handles, zoom feel at multiple sizes, and persistent tool styles. Preserve the existing on-device sensitive-text/faces controls.
4. Refine Quick Access stacking and thumbnail aspect ratio, then complete multi-location save destination selection and persistence.
5. Capture representative editor/save and capture/Quick Access Instruments traces before further performance claims.
6. Decide distribution (Mac App Store, direct, or both), then assess sandboxing, signing, notarization, update delivery, and data migration. Do not implement an updater until that decision is clear.

## Historical design risks from 2026-11-04

- The redesigned Library and editor have been inspected live at the current window size, but minimum-size resizing and dark appearance still need a pass after the latest simplification. VoiceOver verification remains open.
- The Settings sidebar is native and the content uses centered width constraints, but its minimum-size balance still needs live verification.
- Clipboard exclusions still use the frontmost app observed by a polling watcher and cannot guarantee source-app provenance.
- Editor annotation rendering and small originals-index JSON persistence still run synchronously. Interaction traces are still needed before prioritizing more performance work.
- App Sandbox is disabled. Distribution intent is not established.

## Resume checkpoint — 2026-11-04

- Branch remains `feature/stability-and-performance`; there have been no branch, index, commit, remote, or project-file operations this batch. Preserve all dirty changes, including the pre-existing `Untitled.xcodeproj/project.xcproj` edit and recording reliability work.
- Latest UI batch changed `Untitled/Components/GlassSegmentedPicker.swift`, `Untitled/Features/Editor/AnnotationCanvas.swift`, `Untitled/Features/Editor/EditorInspector.swift`, `Untitled/Features/Editor/EditorView.swift`, `Untitled/Features/Library/LibraryView.swift`, `Untitled/Features/Main/MainView.swift`, and this roadmap.
- The editor now uses native segmented Pickers without an extra glass overlay, an automatic Form inside its one glass inspector panel, and a compact native-glass zoom button with a native slider popover. Live click and direct drag were verified; 100% changed to 115%. The Library image/text tile backgrounds and decorative version backplate were removed. Debug sample imagery is solid-color, with no custom UI gradient.
- Selection handles now use a centered opacity-only entrance instead of scaling from zero. Build and 12 tests pass after this edit. The CUA attempt to draw a temporary shape did not create a visible mark, so handle animation is not claimed as visually verified.
- Verification: Xcode build succeeded on macOS 27.2, Swift 6, deployment target macOS 26.0; 12 tests passed, 0 failed; app launch and live UI inspection succeeded for Library, Settings, inspector, native segmented choices, and zoom. `git diff --check` passed after the UI cleanup.
- The multi-location save destination work remains in progress. `SettingsStore` already stores normalized folder paths and a default location; aggregate Library scanning/watchers, add a native per-capture destination choice plus add/remove settings, write migration/persistence tests, and verify.
- Next: check default/minimum layout balance and settings; finish Library selection, Quick Look, context-menu and drag workflows; then redesign editor selection/annotation affordances without adding decorative surfaces. Continue Quick Access stack/aspect ratio and multi-location storage after the shell feels coherent.
- Remaining: live VoiceOver and reduced-transparency checks, manual ScreenCaptureKit lifecycle, annotation-drag performance traces, and distribution decision. Do not claim performance improvements without representative measurements.

## Latest checkpoint — 2026-11-04: save destinations

- Added multi-location capture routing for screenshots, recordings, replay clips, and later editor/Quick Access saves. The Library scans the configured folders together and keeps one watcher per folder; Settings can add/remove locations and choose a default. Removing a location only unregisters it and does not delete its files.
- The first toolbar implementation used a native inline destination Picker when more than one location existed. Its live checkmark appeared stale; the follow-up below replaces it with native menu toggles and rebuilds the menu after selection. The current session override is shared by Capture and Record; keyboard shortcuts continue to use the configured default.
- Added tests for location persistence/normalization, library aggregation, and override fallback when a location is removed. Latest Xcode `Untitled` build succeeded; all 15 tests passed. The app launched successfully. Settings UI was inspected live: the temporary test folder was removed and `/Users/har/Pictures/Untitled` remained the only/default location. The empty temporary directory was removed.
- `git diff --check` passes. The existing `Untitled.xcodeproj/project.xcproj` diff was reviewed for this checkpoint and left untouched. No staging, commit, branch, remote, or history operations occurred.
- The live checkmark issue was resolved in the Destination chooser verification below. Continue editor workflow refinement, especially selection/handle behavior; keep performance claims tied to interaction traces rather than assumptions.

## Editor palette checkpoint — 2026-11-04

- Added a third, persistent Custom palette with twelve editable slots. The native `ColorPicker` sheet is available from Editor settings and from the editor inspector; choosing Custom also updates the canvas swatches and number-key shortcuts (1–9 and 0). Invalid stored data falls back to the built-in palette. Existing Pastel/Vivid selections and per-tool styles remain intact.
- Editor Undo notification tokens are now retained by each `EditorDocument` and removed in its isolated deinitializer, so closing editor documents does not leave block observers registered with the process-wide notification center.
- Live inspection on the current Xcode build covered Editor settings, the custom palette selection and edit button, the twelve native color wells, and the same edit sheet in the active editor. The sheet was cancelled without changes; the existing Pastel preference was restored, and the opened capture was closed without editing or saving it. A dark-mode settings preview was also rendered and inspected.
- Added coverage for custom palette data round-tripping, digit-key mapping, and malformed palette fallback. Xcode build succeeded; all 17 tests passed. `git diff --check` passes.
- The existing `Untitled.xcodeproj/project.xcproj` remains untouched. No staging, commit, branch, remote, or history operations occurred.
- Next: continue the editor selection/handle workflow and accessibility review. The destination chooser follow-up below is complete. Do not claim operation-level performance gains without representative traces.

## Destination chooser verification — 2026-11-04

- Kept the configured save folder as the default for shortcuts and captures. A separate session-scoped override lets the user select another configured folder from either the Capture or Record menu; removing that folder clears the override and falls back to the default.
- The menu's checked item was stale because SwiftUI retained the previously built toolbar menu. The toolbar menu identity now follows the override, which rebuilds the native menu after a selection; its checkmark moves to the selected folder. Capture also exposes the active folder through its accessibility value and help text.
- Live verification used a temporary second folder. Selecting it moved the checkmark in both Capture and Record menus, and the Capture accessibility value named that folder. The selection was returned to the configured default; no screenshot or recording was created. The temporary location was removed from Settings and its empty directory was removed. `/Users/har/Pictures/Untitled` remains the only/default folder.
- Updated the XCTest to cover the session override and fallback when its folder is removed. Xcode build succeeded; all 17 tests passed. `git diff --check` passes.
- Files touched for this follow-up: `Untitled/App/AppDependencies.swift`, `Untitled/Features/Main/MainView.swift`, `Untitled/Services/Settings/SettingsStore.swift`, and `UntitledTests/UntitledTests.swift`. `Untitled.xcodeproj/project.xcproj` was not edited; its existing uncommitted changes remain.
- Next: continue editor selection and handle behavior, then perform VoiceOver checks on custom controls. Manual ScreenCaptureKit, representative interaction/energy traces, and distribution choice remain open.

## Editor annotation accessibility — 2026-11-04

- Live accessibility inspection found that annotation layers were absent from the accessibility tree despite their existing labels and actions. Each saved annotation now exposes a hidden native SwiftUI `Button` representation with its tool label, selected state, keyboard movement hint, and Delete action. The drawing layer remains visually and pointer-input transparent to this change.
- Verified live in the rebuilt editor: a temporary rectangle appeared as an accessible Shape button, reported `Selected` after the selection settled, and exposed its Delete action. The handles aligned to the mark's corners and edge centers. The test mark was undone and the editor was closed without saving; the original capture remains unchanged.
- Xcode `Untitled` build succeeded with zero warnings; all 17 tests passed. `git diff --check` passes. No automated test was added for this view-only accessibility behavior; the live accessibility tree was the verification.
- Files changed in this batch: `Untitled/Features/Editor/AnnotationCanvas.swift` and this roadmap. The pre-existing Xcode project-file diff was not touched. No Git index, branch, remote, or history operations occurred.
- Next: verify VoiceOver navigation through editor tools and inspector controls, then continue the Library selection, Quick Look, context-menu, and drag workflows. Manual ScreenCaptureKit tests, representative performance traces, and the distribution decision remain open.

## Quick Access thumbnail shape — 2026-11-04

- Added a persisted native segmented aspect-ratio setting for Quick Access cards: 4:3, 3:2 (default), and 16:9. All card sizes use the same selected ratio so a stack stays aligned; changing the ratio affects the thumbnail crop only, not the saved capture.
- The Quick Access panel controller applies the new geometry when settings change, including while thumbnails are already visible. Added an XCTest for default selection, all three frame dimensions, and persistence.
- Live verification initially attached to an older running app process; after stopping and relaunching the active Xcode scheme, the settings pane displayed the new picker with 3:2 selected and the crop-only helper text. No preference was changed during visual verification.
- Xcode `Untitled` build succeeded with no warnings; all 18 tests passed. `git diff --check` passes. `Untitled.xcodeproj/project.xcproj` was not edited in this batch; its pre-existing key-order changes and the already-added XCTest target remain in the worktree.
- Files for this batch: `Untitled/Models/CaptureSettings.swift`, `Untitled/Services/Settings/SettingsStore.swift`, `Untitled/App/AppDependencies.swift`, `Untitled/Features/QuickAccess/QuickAccessController.swift`, `Untitled/Features/Settings/QuickAccessSettingsView.swift`, `UntitledTests/UntitledTests.swift`, and this roadmap.
- Next: continue accessibility review in the live editor and Library selection/Quick Look/context-menu/drag workflows. Then profile representative capture, editor, and Quick Access work before making performance claims. Manual ScreenCaptureKit lifecycle verification and distribution choice remain open.

## Editor canvas accessibility — 2026-11-04

- The live editor's accessibility tree exposed the tools, inspector, and zoom, but not the screenshot canvas. The canvas used SwiftUI's explicitly decorative `Image` initializer, so its separate label did not make it a VoiceOver image element.
- Changed the canvas to a semantic SwiftUI image named “Screenshot canvas” with its pixel dimensions as the accessibility value. Rendering, scaling, and pointer interaction are unchanged; annotation layers remain separate accessible elements.
- Verified in the rebuilt editor's live accessibility tree: “Screenshot canvas” appeared as an image with “1,928 by 866 pixels”. The open capture had no edits; it was closed without saving and remains selected in the Library.
- Xcode `Untitled` build succeeded with no warnings; all 18 tests passed. `git diff --check` passes. The project-file change was not touched.
- File changed in this batch: `Untitled/Features/Editor/AnnotationCanvas.swift` and this roadmap. Full VoiceOver navigation and speech verification remain open; the accessibility tree check does not substitute for them.
- Next: verify VoiceOver navigation and keyboard operation across the editor tool palette/inspector, then continue Library selection, Quick Look, context-menu, and drag workflows. Manual ScreenCaptureKit lifecycle verification, representative Instruments traces, and the distribution decision remain open.

## Library Quick Look selection — 2026-11-04

- Fixed a keyboard behavior bug in `LibraryViewModel`: Space previously fell back to the first screenshot when the selection was empty or contained only captured text, so it could open a file unrelated to the user's selection.
- Quick Look now opens only the first selected file, closes an already-open preview, and otherwise does nothing. Added state coverage for text-only selection, empty selection, selected image, and closing the preview.
- Xcode `Untitled` build succeeded; all 19 tests passed. The rebuilt Library was visually inspected and its layout remained intact. `git diff --check` passes. No capture, clipboard contents, or editor documents were modified during the check.
- Files changed in this batch: `Untitled/Features/Library/LibraryViewModel.swift`, `UntitledTests/UntitledTests.swift`, and this roadmap.
- Next: verify Library multi-selection, context menu, Quick Look, and drag behavior without copying test text into the user's clipboard; continue live VoiceOver and editor keyboard checks afterward. Manual ScreenCaptureKit lifecycle verification, representative Instruments traces, and distribution choice remain open.

## Library selection state coverage — 2026-11-04

- Added focused tests for Command-style selection toggling, Shift-style contiguous range selection, and context-menu targets for selected versus unselected captures.
- Live inspection confirmed the Library's native context menu presents Open in Editor, Quick Look, Copy, Pin to Screen, Show in Finder, Share, and Move to Trash. No menu action was run; the original first capture was reselected afterward.
- CUA did not preserve Command as a held click modifier, so real Command-click and Shift-click behavior is not claimed as live-verified. The state model is covered; modifier delivery still needs a real input/manual check. No product defect was inferred from the automation limitation.
- Synthesized right-clicks opened the expected menu but did not update the highlighted cell to match the clicked location. Since the automation did not establish normal hover delivery before the click, right-click selection remains unverified rather than a confirmed app bug.
- Xcode `Untitled` build succeeded with no warnings; all 20 tests passed. `git diff --check` passes. No files were opened in another app, copied, moved, or deleted during this check.
- File changed in this batch: `UntitledTests/UntitledTests.swift` and this roadmap.
- Next: verify modifier selection with actual keyboard/mouse input when available, then check Library Quick Look and drag behavior. Continue VoiceOver navigation and editor keyboard checks; manual ScreenCaptureKit, Instruments traces, and distribution choice remain open.

## Library accessibility actions — 2026-11-04

- Added named SwiftUI accessibility actions to capture cards so assistive technology can open screenshots in the editor, open recordings in their default app, and invoke Quick Look. Card click still selects; the existing keyboard and context-menu behaviors are unchanged.
- Rebuilt and launched the current Xcode project. The live accessibility snapshot confirms Library cards remain buttons with their title and metadata. This snapshot does not list SwiftUI named VoiceOver rotor actions, so VoiceOver interaction still needs a manual check; Apple documents `accessibilityAction(named:)` as an action for assistive technologies.
- Xcode `Untitled` build succeeded with zero warnings; all 20 tests passed. `git diff --check` passes. No capture was opened or changed during this verification.
- File changed in this batch: `Untitled/Features/Library/LibraryView.swift` and this roadmap. No Git index, branch, remote, or history operations occurred.
- Next: manually confirm named card actions with VoiceOver; continue Library drag/keyboard navigation checks and then move into editor interaction/performance refinement. Manual ScreenCaptureKit lifecycle tests, representative Instruments traces, and distribution choice remain open.

## Editor highlighter interaction path — 2026-11-04

- Reduced work performed for each highlighter pointer update in `HighlightSnapping`: stroke bounds now use one pass, nearest matching line is selected without allocating a candidate array, touched words use scalar bounds instead of filtered/map arrays, and block highlighting builds/sorts only its final bands.
- Kept the existing median, line tolerance, word-overlap threshold, and top-to-bottom order. Added tests for the nearest-line/whole-word result and block-band ordering. The optimization reduces repeated passes and temporary collections; no numeric latency claim is made because no Instruments benchmark was captured.
- Xcode `Untitled` build succeeded with zero warnings; all 22 tests passed. The rebuilt editor and inspector were inspected live. A synthetic drag did not create a stroke in CUA, so the actual pointer-drag path remains to be checked with real input; the open capture was closed without saving and remains selected in the Library.
- Files changed in this batch: `Untitled/Features/Editor/HighlightSnapping.swift`, `UntitledTests/UntitledTests.swift`, and this roadmap. `git diff --check` passes. Existing project-file and recording changes remain untouched; no staging, commit, branch, remote, or history operations occurred.
- Next: verify editor drawing and resize interactions with real mouse input, profile representative annotation/blur cases before further performance claims, then continue the editor workflow review. Full VoiceOver navigation, manual ScreenCaptureKit lifecycle tests, and distribution choice remain open.

## Library filter update path — 2026-11-04

- The Library view previously filtered and re-merged/re-sorted all files and snippets every time its body ran, including selection and pointer-driven redraws. `LibraryViewModel` now builds the newest-first source only when folder contents or text history change, then refreshes its stored visible list only when sources, search text, or kind filter change. Selection-only redraws reuse the current list.
- Selection pruning now happens with source updates, avoiding a second merge/sort for the same data change. Matching rules and newest-first ordering are unchanged.
- Added coverage for mixed date ordering, screenshot/text filters, search results, and pruning a selected item that disappears from the source.
- Xcode `Untitled` build succeeded with zero warnings; all 23 tests passed. The rebuilt Library was inspected live: Recordings showed the two recording rows; searching “Replay” narrowed it to the matching replay; clearing search and returning to All restored the original Library selection and list. No captures, clipboard data, or settings were changed.
- Files changed in this batch: `Untitled/Features/Library/LibraryView.swift`, `Untitled/Features/Library/LibraryViewModel.swift`, `UntitledTests/UntitledTests.swift`, and this roadmap. `git diff --check` passes. The original project-file and recording changes remain untouched; no staging, commit, branch, remote, or history operations occurred.
- Next: profile library scrolling/search and annotation drawing with representative data before stating latency gains; verify real pointer-drag and VoiceOver actions when interactive verification is available. Manual ScreenCaptureKit lifecycle tests and distribution choice remain open.

## Settings window sizing — 2026-11-04

- Changed the Settings scene from content-size resizability to SwiftUI's native `contentMinSize` strategy. The Settings view keeps its existing 820 × 560 minimum and 720-point form measure, while the scene no longer declares a maximum size. This follows Apple's `WindowResizability` guidance for minimum content sizing with no maximum.
- Built and ran the Xcode `Untitled` scheme after the change. Build succeeded with zero warnings; all 23 XCTest cases passed.
- Inspected the current Xcode-built app, not an older installed copy. The nine-section Settings sidebar and grouped controls render as expected. macOS Window › Move & Resize › Left was exercised and the Settings content remained legible; the Window menu's Zoom item still reports disabled, so the window's full manual resize/zoom behavior is not yet verified and needs follow-up before claiming this complete.
- Changed `Untitled/App/UntitledApp.swift` and this roadmap. `git diff --check` passes. The existing project-file, recording, and other user changes remain preserved; no staging, commit, branch, remote, or history operations occurred.
- Next: resolve the Settings zoom/resizing limitation with a live window-size check, then continue Library/editor interaction refinement and representative performance profiling. Full VoiceOver checks, ScreenCaptureKit lifecycle verification, and the distribution decision remain open.

## Library and Clipboard preview alignment — 2026-11-04

- Added one shared 3:2 preview frame and compact 8-point corners for Library and Clipboard cards. Thumbnails use aspect-fit inside a subtle system quaternary surface, so portrait and landscape captures keep their full content while every card presents the same shape. Text previews use the same frame. Quick Access keeps its separate 4:3, 3:2, and 16:9 preference.
- Matched the Quick Look thumbnail request to the largest 320 × 214 point preview. The existing 64 MB `NSCache` limit still bounds thumbnail memory; larger previews may evict older thumbnails sooner, so scrolling through very large histories remains a profiling item.
- Xcode `Untitled` build succeeded with zero warnings; all 23 tests passed. The current Xcode-built Library was visually checked at its default width and using macOS half-screen tiling: the grid changed from five columns to three, previews kept the same shape, image content was not cropped, and captions remained readable. Clipboard cards use the same shared sizing in source; live Clipboard contents were not opened during this check.
- Changed `Untitled/Components/FileThumbnail.swift`, `Untitled/Features/Library/LibraryView.swift`, `Untitled/Features/Clipboard/ClipboardView.swift`, and this roadmap. `git diff --check` passes. Existing user changes, including `Untitled.xcodeproj/project.xcproj`, remain present; nothing was staged, committed, pushed, merged, or switched.
- Next: continue Library Quick Look, keyboard, and drag behavior; then refine editor selection/resize interactions and measure representative work. Settings Zoom still reports disabled after the prior `contentMinSize` change and needs a direct follow-up. VoiceOver, manual ScreenCaptureKit lifecycle, Instruments profiling, and distribution choice remain open.

## Library keyboard selection — 2026-11-04

- Added arrow-key selection through the visible Library grid. Left and Right move by one card; Up and Down move by the current row width. Shift plus an arrow extends selection from a stable anchor, including across partial rows. Escape clears selection.
- Kept navigation position separate from the Shift-selection anchor. Clearing selection resets both, and source updates prune anchors that no longer refer to a capture.
- The ScrollView consumes arrow keys for scrolling, so the Library now uses a scoped local AppKit event monitor while its grid has focus. It leaves text editors and other modifiers alone, and handles clicks in the same monitor used for right-click selection.
- Added state tests for movement, range extension, boundaries, and clearing. Xcode `Untitled` build succeeded with zero warnings; all 24 tests passed.
- Visually tested the rebuilt app at its normal width and macOS half-screen tile. Arrow movement and Shift+Down selected the expected row-major range at both widths; the grid used five columns at normal width and three when tiled. Restored the original window size and cleared the temporary selection. No capture, clipboard item, or setting was modified.
- Changed `Untitled/Features/Library/LibraryView.swift`, `Untitled/Features/Library/LibraryViewModel.swift`, `UntitledTests/UntitledTests.swift`, and this roadmap. `git diff --check` passes; existing project-file, recording, and other user changes remain intact. Nothing was staged, committed, pushed, merged, or switched.
- Next: refine editor selection/resize performance. Settings Zoom, VoiceOver, manual ScreenCaptureKit lifecycle tests, Instruments profiling, and the distribution decision remain open.

## Editor zoom scrub — 2026-11-04

- Kept the editor’s direct zoom scrub and native SwiftUI numeric text transition. Added an explicit top attachment edge for the slider popover so it opens toward the canvas from the bottom status control.
- Visually verified the rebuilt editor’s slider and presets in the expanded window. At the prior shorter window size, the accessibility tree exposed the complete native popover, while the app-window screenshot showed only its lower edge; direct screen-level placement at that size remains a follow-up check.
- A short up-right drag changed zoom from 100% to 122%; the native 100% preset restored it. Restored the editor window to its prior size and left the screenshot unsaved and otherwise unchanged.
- Xcode `Untitled` build succeeded with no errors; all 24 XCTest cases passed. The build log includes a Swift weak-capture warning at `Untitled/Services/Recording/ScreenRecorder.swift:447` and the App Intents metadata skip because the target does not link `AppIntents`.
- Changed `Untitled/Features/Editor/EditorView.swift` and this roadmap. `git diff --check` passes. Existing changes, including the project-file and recording edits, remain preserved; nothing was staged, committed, pushed, merged, or switched.
- Next: verify the zoom popover at short window sizes, then exercise editor mark selection and resize at multiple zoom levels. VoiceOver, manual ScreenCaptureKit lifecycle tests, Instruments profiling, and distribution choice remain open.

## Editor annotation drag updates — 2026-11-04

- The editor now captures selected annotation indices when a move gesture begins and updates those marks directly for each pointer sample. This removes the full annotation-list membership scan from the hot drag path; the cached indices are range- and selection-checked before use. Keyboard nudging retains its simpler one-shot selection scan.
- Added a state test that moves a two-mark selection among 128 unrelated annotations and verifies that unrelated marks stay fixed and undo restores the original document.
- The rebuilt editor was visually checked: a temporary arrow drew and moved under the pointer, then undo removed both test changes. Zoom returned to 100%, the default arrow shadow remained off, and Undo is disabled. No capture was saved or changed.
- Xcode `Untitled` build succeeded; all 25 XCTest cases passed. This is a bounded reduction in work per drag event; no latency improvement is claimed without an Instruments trace.
- Changed `Untitled/Features/Editor/EditorDocument.swift`, `UntitledTests/UntitledTests.swift`, and this roadmap. `git diff --check` passes. Existing project-file, recording, and other edits remain preserved; nothing was staged, committed, pushed, merged, or switched.
- Next: continue editor resize/handle behavior at multiple zoom levels and verify the zoom popover at short window sizes. VoiceOver, manual ScreenCaptureKit lifecycle tests, representative Instruments profiling, and distribution choice remain open.

## Editor zoom popover placement — 2026-11-04

- Live inspection reproduced the zoom slider popover opening beneath the bottom status control, where the window clipped it. SwiftUI's `.top` arrow edge attaches the popover below its anchor.
- Changed the popover to use `.bottom`, which places the native popover above the anchor. Rebuilt and relaunched the app; the title, percentage, slider, Fit, and 100% controls are now fully visible in the live editor.
- Verified zoom remains at 100%, Undo is disabled, and the open screenshot has no unsaved annotation changes. No XCTest was added for this one-line placement correction; the app build and live visual check cover the behavior.
- Changed `Untitled/Features/Editor/EditorView.swift` and this roadmap. Xcode `Untitled` build succeeded; no tests were run for this layout-only change. `git diff --check` passes. The project-file diff remains 37 insertions / 2 deletions, matching the preserved change. Nothing was staged, committed, pushed, merged, or switched.
- Next: verify editor mark selection and resize at multiple zoom levels, including a genuinely short window size if it can be reached without confusing window-resize gestures with canvas input. VoiceOver, manual ScreenCaptureKit lifecycle tests, representative Instruments profiling, and distribution choice remain open.

## Settings window behavior check — 2026-11-04

- Targeted the app built by the active Xcode workspace, rather than the separate `/Applications/Untitled.app` copy. The live General pane's content is centered within the detail column, and the native Settings sidebar is present.
- The Settings window's Zoom command remains disabled. An explicit `.windowResizeBehavior(.enabled)` on `SettingsView` did not change the live accessibility state, so that trial was removed. Keep the native Settings scene; do not add AppKit window manipulation without a reproducible user-facing resize failure.
- Xcode `Untitled` build succeeded with the final source. No tests were run because no source change remains. Window-edge resizing was not verified. `git diff --check` passed; no user changes were overwritten and no Git history or staging operation occurred.
- Next: verify a real Settings window edge resize if needed, then continue editor resize/handle checks. VoiceOver, manual ScreenCaptureKit lifecycle tests, representative Instruments profiling, and the distribution decision remain open.

## Editor handle drag lookup — 2026-11-04

- A handle drag now captures the selected annotation's array index and ID when the gesture starts. Each pointer sample uses that index directly and checks the ID before mutation, avoiding the selected-mark and array searches on the hot path while remaining safe if the array changes.
- Added an XCTest that reshapes one selected arrow among 128 unrelated annotations and verifies both untouched marks and undo restoration.
- Xcode `Untitled` build succeeded; all 26 tests passed. The live editor was checked at 100% and 125% zoom: a curve handle and an endpoint handle followed their drags. Three undo operations removed the temporary test arrow, Undo became disabled, zoom was restored to 100%, and the editor was closed with “Don't Save”; the Library capture was not changed.
- Changed `Untitled/Features/Editor/EditorDocument.swift`, `UntitledTests/UntitledTests.swift`, and this roadmap. `git diff --check` passes. The existing project-file change remains 37 insertions / 2 deletions; no staging, commit, push, merge, or branch change occurred.
- Next: verify actual editor window resizing at smaller sizes, check VoiceOver navigation through the custom editor controls, then continue performance work with measured traces. Manual ScreenCaptureKit lifecycle testing and the distribution decision remain open.

## Editor popup placement and recording callback warning — 2026-11-04

- The zoom control now uses SwiftUI's default popover edge selection instead of forcing one edge. This leaves placement to the native presentation system when the editor sits near a display edge or has limited vertical room.
- The Xcode-built editor was reopened on the existing capture with zoom at 100%. Its accessibility tree exposed the native popover title, slider, Fit, and 100% controls. The app-level screenshot did not clearly show the popover body at the window's lower edge, so visual placement is not claimed as verified and remains a follow-up.
- The ScreenCaptureKit system-stop callback now weakly captures the recorder in its main-actor task. This removed the Swift weak/strong capture warning without changing the stop/finalize flow.
- Xcode `Untitled` build succeeded. All 26 XCTest cases passed. The only build-log warning is Xcode's App Intents metadata extraction skip because the app does not link `AppIntents`; no Swift source warning remains. `git diff --check` passes.
- Changed `Untitled/Features/Editor/EditorView.swift`, `Untitled/Services/Recording/ScreenRecorder.swift`, and this roadmap. The project-file diff remains 37 insertions / 2 deletions. The sample capture was not saved or edited; no changes were staged, committed, pushed, merged, or switched.
- Next: confirm zoom popover placement with a full display view at a short editor size, then continue VoiceOver/keyboard verification and representative profiling. Manual ScreenCaptureKit lifecycle tests and distribution choice remain open.

## Editor runtime layout diagnostics — 2026-11-04

- Xcode's live console for the editor session recorded repeated AppKit `Invalid view geometry` faults for negative widths and heights, plus one `layoutSubtreeIfNeeded` recursion error while the editor was active.
- The log entries identify AppKit but provide no app call site or stack. The inspector and canvas contain geometry-dependent layout, but the current evidence does not prove which view emitted the invalid size; no speculative layout clamp was added.
- Next: reproduce under an AppKit layout-recursion breakpoint and isolate the negative-size source before changing editor layout. Keep this ahead of further animation/performance tuning because invalid geometry can trigger extra layout work and visual instability.

## Editor inspector content sizing — 2026-11-04

- Reproduced the full-height glass panel in the live Xcode-launched editor after hiding and restoring the inspector. The prior stateful scroll-geometry height measurement was not reliable for compact content, so it has been replaced with `InspectorPanelLayout`: it gives the available height to `ViewThatFits`, reports the selected child’s size, and uses a native `ScrollView` only when the content exceeds the available room.
- The existing native controls and system `.glassEffect(.regular)` surface are retained. Panel size changes follow the selected tool with a short native smooth animation; the sizing path has no polling or geometry-state feedback loop.
- Xcode previews on macOS 27.0.1 show Select and Spotlight panels fitted to their controls, Arrow content fitted at normal height, and Arrow scrolling at a constrained height. The running editor was not relaunched after this final change because it has an open document with possible unsaved state; only the previews show the final source version.
- Xcode `Untitled` build succeeded and all 26 XCTest cases passed. `git diff --check` passes. The project-file diff remains 37 insertions / 2 deletions. No staging, commit, push, merge, or branch change occurred.
- Changed `Untitled/Features/Editor/EditorInspector.swift` and this roadmap. Next: verify this final layout in the live editor when its open document is safely preserved, then continue editor resize/drag and accessibility checks. Manual ScreenCaptureKit lifecycle testing, Instruments profiling, and distribution choice remain open.

## Main shell, Settings, and native filter live review — 2026-11-04

- Inspected the Xcode-launched app at runtime. The General and Editor Settings panes use the native Settings sidebar and grouped SwiftUI forms; the nine destinations match the intended macOS preference categories. The Editor pane's palette is a system segmented picker with persistent palette and tool-style controls. No layout defect was reproduced at the current window size.
- The Library filter opens as a native macOS menu with All, Screenshots, Recordings, and Text. It was dismissed without changing the active filter. The zoom popover was also visibly positioned above its bottom status control, with the title, slider, Fit, and 100% options on screen.
- The open editor document was left untouched. The zoom's native accessibility Increment action changed the value from 100% to 125% and visibly enlarged the canvas; Decrement restored 100%. No annotation was saved, undone, or closed. Direct pointer scrubbing could not be verified with the available UI coordinate targeting; treat zoom-drag verification as outstanding rather than as a source failure.
- This was a visual review only: no application source changed and no build or test was run in this pass. The prior batch's Xcode build and 26 passing tests remain the latest test evidence. `git diff --check` passed before this roadmap entry; the preserved project-file diff remains 37 insertions / 2 deletions.
- Next: verify zoom scrubbing through reliable window-aware input or a focused interaction test, then continue editor resize and VoiceOver checks. Manual ScreenCaptureKit lifecycle testing, Instruments profiling, and the distribution decision remain open.

## Editor inspector compact sizing correction — 2026-11-04

- The running editor still showed a full-height Spotlight glass panel. Source inspection found that the custom layout measured `ViewThatFits` with the full available height, so its reported size could preserve the large proposal instead of hugging the selected content.
- `InspectorPanelLayout` now measures its single `ViewThatFits` child at natural height first. It applies the height limit only when the content exceeds the available room, allowing the system scroll fallback to take over. An initial two-child custom-layout attempt was discarded after previews showed both branches rendering; the final layout retains one `ViewThatFits` child.
- Xcode previews on macOS 27.0.1 show the Select and Spotlight inspectors fitted to their controls, the Arrow inspector fitted with all 12 palette colors visible, and the Arrow inspector scrolling in constrained height without duplicate controls. Light and dark Spotlight previews were checked.
- The Xcode `Untitled` build succeeded with no build-log warnings. All 26 XCTest cases passed. `git diff --check` passed. The existing editor was not relaunched because it contains possible unsaved annotation work; the new sizing is preview-verified but still needs live confirmation when that document is safe to preserve.
- Changed `Untitled/Features/Editor/EditorInspector.swift` and this roadmap. The existing Xcode project-file diff remains 37 insertions / 2 deletions. Next: verify the rebuilt inspector in the live editor without disturbing the open document, then finish direct zoom scrub and editor resize/accessibility checks.

## Zoom scrub direction refinement — 2026-11-04

- The zoom gesture previously computed `horizontal - vertical`, which makes equal right/down or left/up diagonals produce no movement. `ZoomScrub.distance(for:)` now follows the dominant pointer axis, with horizontal movement winning ties; right/up zoom in and left/down zoom out.
- Added `testZoomScrubFollowsDominantAxisWithoutDiagonalCancellation` for horizontal ties and vertical-dominant movement. The previously verified native accessibility increment/decrement still provides a reversible way to confirm zoom state changes, but direct pointer delivery remains unverified because UI coordinate targeting did not reach the control.
- Xcode `Untitled` build succeeded with no warnings. All 27 XCTest cases passed. The compact inspector previews remain the visual evidence for the immediately preceding editor batch; this math-only change does not alter layout. The running editor remains open with possible unsaved annotation work and was not restarted.
- Changed `Untitled/Features/Editor/EditorView.swift`, `UntitledTests/UntitledTests.swift`, and this roadmap. `git diff --check` passes; the existing project-file diff remains 37 insertions / 2 deletions. Next: complete live pointer-drag and editor resize/VoiceOver checks when safe, then continue the editor workflow.

## Quick Access thumbnail rendering off the capture path — 2026-11-04

- `QuickAccessController.show(_:)` previously performed a full Core Graphics downsample synchronously before the Quick Access panel appeared. With the app's MainActor default isolation, that work ran on the UI path immediately after capture completion.
- The stack now inserts and displays a lightweight `NSImage` wrapper first, then renders its Retina-sized copy in a cancellable detached task. Results apply on the main actor only while the card still exists, the request token is current, and the card size still matches. Dismissal and size changes cancel stale work; render failure keeps the original image. No-upscale behavior and existing aspect-fill crop are preserved.
- Size changes keep the current card image visible until the replacement is ready. This avoids temporarily switching every card back to a full-resolution source image during a settings change.
- Added renderer tests for a 4,000 × 2,000 image producing the expected 904 × 452 thumbnail at the 340 × 226 card size, and for not upscaling a smaller source. Added geometry coverage for the 3:2 card shape, collapsed peeks, hidden older cards, and ordered expansion. Xcode `Untitled` build succeeded with zero warnings; all 30 XCTest cases passed.
- Added Xcode-only previews for the collapsed stack, expanded column, and hover actions. Xcode rendered each in both light and dark appearance; the stack stays physically aligned, and the glass action buttons remain legible. The card surface and context menu were split into small view expressions after the preview compiler hit a type-checking limit; the menu items and runtime behavior are unchanged.
- The running app was not relaunched because its editor may hold unsaved work; live Quick Access replacement timing remains unverified. This batch establishes that raster downsampling is no longer synchronous on the capture UI path, but no latency claim is made until an Instruments trace is recorded.
- Changed `Untitled/Features/QuickAccess/QuickAccessController.swift`, `Untitled/Features/QuickAccess/QuickAccessThumbnail.swift`, `UntitledTests/UntitledTests.swift`, and this roadmap. `git diff --check` passes. The preserved project-file change remains 37 insertions / 2 deletions; no Git index or history operation occurred.
- Next: verify the Quick Access stack with a safe synthetic capture or when the editor document can be preserved, then record a representative capture-to-panel timing trace. Continue editor resize and VoiceOver checks afterward; manual ScreenCaptureKit lifecycle tests and the distribution decision remain open.

## Previous checkpoint — 2026-11-04: retrace identity, redaction, and reliability

- Product identity is now `retrace` in Xcode's product, executable, display name, app icon, menu-bar asset, metadata descriptions, and default filename template. The existing project path/target/scheme/module/bundle ID and `Pictures/Untitled` compatibility paths were retained; the exact impact inventory is in `ENGINEERING_HANDOFF.md`.
- Confirmed and fixed the blur/mosaic fail-open path: preview covers requested redactions until the layer is ready; export fails closed for unavailable redaction layers. Added two pixel-level regression tests.
- Added strict normalization for persisted quality, frame-rate, countdown, replay-size/duration, and Quick Access delay settings. Concurrent recording/replay output reservations now receive distinct paths. Image export now fails if resizing/color conversion or metadata verification cannot complete.
- Local commits since the previous checkpoint: `33cbc4c`, `ee2b059`, `0cc5ee2`, `7acc097`, `bfc59d3`, `cb60fb2`, and `c7a5097`. No push, merge, reset, amend, rebase, or squash occurred.
- Xcode MCP build and launch succeeded. All 36 current XCTest tests passed; Xcode reported no warnings; `git diff --check` passed. The built product contains retrace_app icons in Assets.car and retrace_app.icns.
- Apple documentation/release check was made on 2026-11-04: macOS 27.2 stable and macOS 27.3 beta 1 are distinguished in the handoff. The app still targets macOS 26.0.
- Remaining: live VoiceOver and resizing checks, representative Instruments measurements, interactive clipboard and ScreenCaptureKit lifecycle checks, and review/commit of the larger existing worktree. Standalone command-line Analyze failed in actool while opening the Icon Composer document; Xcode MCP build/test succeeds, but static analysis is not claimed.

## Historical checkpoint — 2026-11-05: native UI, editor, storage, and Xcode setup

- Completed and committed the Library/Clipboard/Settings UI pass, configurable multi-folder storage, per-capture session destinations, Quick Access crop ratios and background thumbnail rendering, editor interaction/accessibility and asynchronous saves, custom editor colors, and ScreenCaptureKit finalization handling.
- Source checkpoint c630108 was 21 commits ahead of origin/main. Eight source commits followed the prior checkpoint. See ENGINEERING_HANDOFF.md for the current source commit inventory.
- Xcode is open to the original Untitled.xcodeproj with shared retrace active, legacy shared Untitled retained, My Mac selected, app version 0.1.0 (build 1), and macOS 26.0 deployment target. The generated retrace product launches.
- At that checkpoint Xcode MCP reported 42 tests passed, no failures/skips/not-run cases. The latest build warning and the expanded UI/capture verification are documented in the current checkpoint above and ENGINEERING_HANDOFF.md.
- Product naming and signature impact are recorded in the handoff. Automatic local signing is set with the existing Personal Team, but the machine has zero valid identities; distribution is not established. Sandbox and bundle identity remain unchanged.
- Apple documentation was checked 2026-11-05: macOS 27.2 stable; 27.3 beta, released Nov 3, is tracked separately. The current Xcode 27.2 stable toolchain is used and no beta-only APIs were added.
- Remaining priorities from that earlier checkpoint were expanded after the crash fix and live capture checks; see ENGINEERING_HANDOFF.md.

## Earlier checkpoint — 2026-11-05: area capture, replay timer, and workspace navigation

- Fixed the area-capture crash: AppKit's window list can contain `4294967296`, which cannot be represented by `CGWindowID`. Checked conversion now rejects null/out-of-range identifiers without trapping. A regression test covers the 32-bit boundary.
- Xcode MCP launched the existing Retrace app, captured an area PNG, and created a short area MOV. The app remained responsive. This confirms the reported flow; display/window modes, audio, cancellation, long duration, and replay finalization still need individual live checks.
- Added centered Library/Editor/Settings navigation to the existing main window, preserved Library/Clipboard destinations, rebuilt settings categories as a sidebar list, removed the redundant sidebar toggle, and added an empty Editor drop zone with Choose Image and Browse Library actions. Live review covered Library, Editor, and Settings.
- Added replay-buffer timer state that counts up and caps at the configured duration. At the cap, the red dot pulses while the buffer continues recording and rotating old footage. The menu-bar logo remains. Three tests cover timer boundaries and normal direct-recording time.
- Source commits since the prior checkpoint: `e1d45c0`, `95978c6`, and `b05c71d`; the following Vision work is recorded in the current checkpoint below. The docs-only commit was 26 ahead of origin/main at that point. No history rewrite, push, or merge occurred.
- Xcode reported 47 tests passed at that checkpoint. Local signing configuration builds and launches, but no valid signing identity is installed and strict signature trust verification fails. Distribution signing is not established.

## Latest checkpoint — 2026-11-05: person privacy and saliency crop

- Added a People action alongside Faces, Personal Text, and All Text. It uses `VNDetectHumanRectanglesRequest`; results are expanded slightly, clipped to image bounds, and inserted as separate editable redaction marks.
- Added an on-device `VNGenerateAttentionBasedSaliencyImageRequest` path that suggests a crop around the strongest region. The user sees progress or a recoverable message, can adjust the framing, and can undo the crop. Invalid and out-of-bounds rectangles are rejected or clamped.
- Added crop bounds/undo coverage and Vision smoke checks against a generated blank image. All 50 XCTest tests passed. The existing app built and launched, and the latest warning query was empty. Real-photo Smart Crop/person-detection quality still requires a user-selected image.
- Source commit: `fd1a75e`. The docs-only refresh follows this source checkpoint; the branch is 28 commits ahead of origin/main after that commit. No push or merge occurred.
- Next: complete the live ScreenCaptureKit lifecycle matrix; verify Vision privacy features against a user-selected image; finish accessibility and appearance checks; profile representative workloads; and continue with the remaining features listed in ENGINEERING_HANDOFF.md.
