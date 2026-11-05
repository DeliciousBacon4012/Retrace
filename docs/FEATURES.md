# Retrace: what I want

**How to edit this file**

- One feature per line. Delete a line to drop it, add a line to want it.
- Move a line to **Up next** to make it the priority.
- `[ ]` want it · `[~]` built, needs a real check · `[x]` built and confirmed working
- Add or rename sections freely. Nothing else depends on this layout.

## Up next

<!-- Move lines here. Claude works top to bottom. -->
- [ ] Go through every window and menu with Computer Use, frame by frame, and fix spacing, misalignment and wasted space
- [~] Check that thumbnail hover, close and click feel smooth, with no chop

## Rules for Claude

- Look and feel: native Apple Liquid Glass everywhere, never faked. No old-style controls.
- Only Apple's newest native APIs for glass and materials. No imitation glass of any kind.
- Input: think through everything a person can do in each screen: two-finger swipes, scrolling, click and drag to select.
- Shape: capsules everywhere, not rectangles.
- Motion: real physics-based Apple animations, never linear or keyframe-looking.
- Speed: snappy like CleanShot X. Lightweight, no lag, no crashes.
- Settings: if it can be a preference, make it customizable, and keep it through restarts and macOS updates.
- Design: follow Apple's Human Interface Guidelines. Everything should feel logical and intuitive. Clean, not slop.
- Colors: soft pastels by default, not loud neon.
- Inspiration: [CleanShot X](https://cleanshot.com/), [Shottr](https://shottr.cc/), [ReplayMac](https://github.com/picccassso/ReplayMac). Learn from ReplayMac, but don't copy its code.
- Testing: run the real app and click through it. Don't call something done just because it builds.
- Usage limits: at about 98% of the 5-hour or weekly limit, finish the current step, record a checkpoint, and pause until I say "Continue".

## Capture

- [~] Capture area, window and full screen
- [~] Sharp, highest-quality screenshots, not blurry
- [~] Capture individual windows with custom padding and drop shadow
- [~] Capture Text from the menu bar and main window, choosing an area first
- [~] Choose the save folder, default format and compression
- [~] Strip all metadata
- [~] Detect Screen Recording permission on its own, with a way to recheck it

## Thumbnails

- [x] Floating thumbnail after each capture
- [x] Stack with edges showing how many there are; floors rise on hover
- [~] Choose the corner (default bottom left) and fade speed
- [~] Flick a thumbnail off the screen with physics
- [x] Click to open in the editor
- [x] Hover buttons: copy, delete, pin, close
- [x] Right-click menu
- [~] Drag a thumbnail into any app

## Editor

- [x] Undo and redo that behave properly
- [x] Select All, drag-select and move several marks together
- [~] Shift-click marks, and restyle, nudge or reorder several together
- [x] Drag the zoom number to zoom
- [x] Full toolbar visible at small window sizes
- [~] Window opens at the right size for the image
- [~] Fast, smooth resizing
- [~] Remember each tool's settings, using iCloud when available
- [x] Highlighter snaps to text with OCR, with a real marker look
- [~] Shift-drag the highlighter across lines to highlight them all
- [~] Spotlight tool: oval or rectangle, with adjustable dimming, contrast and background blur
- [~] Redaction that truly removes what's underneath
- [~] Photoshop-style crop: handles already on the image, locked aspect ratios, Enter to apply
- [~] Floating glass inspector with three dots to drag it, or as its own window
- [x] Tools in the window toolbar (other positions dropped by request), inspector on either side, remembered
- [~] Glass menus and controls in the inspector, with a well-placed scrollbar
- [~] Copy Text from an area in the editor
- [~] Open from Clipboard into the editor

## Library

- [x] Instant clicks, ⌘A, Shift-click and right-click menus
- [~] Double-click opens the editor
- [~] Quick Look toggle: single click previews
- [~] Edited captures show their edit, with the original available behind them
- [~] Captured text appears in Recents

## Clipboard history

- [~] Separate tab with images and text from any app
- [~] Keep forever by default, or limit by age or item count in Settings

## Recording and replay

- [~] Record with system audio
- [~] Menu bar timer and countdown, instead of the purple indicator
- [~] Start, stop and Save Last from the menu bar
- [~] Custom Save Last lengths
- [~] Save Last is fast and never cuts the video

## Depth and customization

- [~] Encoder, codec (H.264, HEVC, ProRes), quality, color space, and frame buffer settings
- [~] Replay frame rate, resolution, and quality
- [~] Cursor motion blur with Fast and Quality modes and an amount
- [~] Show clicks in recordings
- [~] Blur preview: Fast or Quality
- [~] Search inside images (text and what Vision recognizes), on this Mac
- [~] Find Similar images
- [~] Identify Image in the editor
- [~] Smart Crop: Attention, Objects, or Document
- [~] Text recognition: Accurate or Fast
- [~] Translate captured text and clipboard items with Apple's translation
- [~] Editor inside the Editor tab, or in its own window

## Notifications

- [x] Notice at the top of the screen after copying text
- [~] Set how long each kind stays up
- [~] Hover for actions like Open in TextEdit, as plain text

## Pin

- [~] Pin a capture on top of other windows, and resize it

## App and Settings

- [~] Works mainly from the menu bar, like CleanShot; the main window has Library and Editor tabs, and Settings is a ⌘, window with a segmented picker
- [~] Slide across Settings tabs without clicking each one
- [~] Memory use and memory limits in Settings

## Bugs to check

- [ ] Main window went back to its default size and position after a rerun from Xcode
- [ ] Capture Area leaves out Retrace's own windows: keep or change?
- [~] Toolbar Right with inspector docked right was hiding the tools

## Ideas I haven't decided on

<!-- From the app's old roadmap. Some may already exist. Delete what you don't want. -->
- [ ] Soft, slowly moving blurred gradient background
- [ ] Timed capture
- [ ] Scrolling capture
- [ ] Snap selection to windows and UI elements
- [ ] Fixed-size and aspect-ratio capture presets
- [ ] Hide desktop icons during capture
- [ ] Freeze the screen while selecting
- [ ] Restore the last closed thumbnail
- [ ] Copy as Markdown or HTML
- [ ] Magnifier tool
- [ ] Rounded corners and backdrops in the editor
- [ ] Rotate, flip, resize and expand the canvas
- [ ] Save editable project files
- [ ] Combine several captures
- [ ] Trim recordings and export GIFs
- [ ] Show keystrokes in recordings
- [ ] Webcam overlay
- [ ] Replay auto-start, pause on battery or lock, and markers
- [ ] Tags, favorites and auto-delete
- [ ] Floating shelf and drop zones
- [ ] Sync all settings across Macs
- [ ] Custom upload destinations
- [ ] Color picker
- [ ] Pixel ruler
- [ ] Draw on screen live
- [ ] HDR recording
- [ ] Summarize or rename captures with Apple Intelligence
