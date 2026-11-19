# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

Recorded as `ios` by the user's choice so Impeccable applies Apple HIG guidance. The real target is **native macOS 15+** (SwiftUI + AppKit, ScreenCaptureKit), a menu bar app (`LSUIElement`). Apply HIG in its macOS form: menu bar extras, keyboard-first, Settings window conventions, no iOS-only patterns (tab bars, sheets from the bottom, touch-size-first layouts). macOS only; no Windows.

## Users

Developers and designers who take and share screenshots many times a day: UI bug reports, PR and docs screenshots, design feedback. They work keyboard-first, mid-task, and want to get back to what they were doing.

## Product Purpose

Capture an area, mark it up, wrap it in a background and copy it, all on the screen where it was taken, with no editor window. Success is a screenshot that looks finished and polished the moment it is pasted.

## Positioning

The exported image is the point. Shiny Screenshot competes with CleanShot X, Shottr and native ⇧⌘4 on how good the pasted result looks (wallpapers, gradients, padding, roundness, shadow, social size presets), produced in place on the capture overlay rather than in a separate editor.

## Operating Context

- Triggered by global shortcuts (⇧⌘2 area, ⌥⇧⌘2 window, ⌃⇧⌘2 repeat last) or the menu bar.
- The selection itself is the editor: toolbar appears under the selection; single-key tools (A R H S B N T P), Esc steps back, Return/⌘C copies, ⌘S saves, ⌘Z undoes.
- Background panel beside the selection; post-capture corner card for drag-out, save, pin, reopen-editable.
- Extra modes: full screen, scrolling capture, delayed capture, Recent (last five).
- Library window (⌘L): saved captures, grouping, sort, filter, tags, edit again with annotations intact.
- Settings window: shortcuts, save folder, login item, updates.

## Capabilities and Constraints

- Swift 6, SwiftUI, MainActor default isolation; built with XcodeGen (`project.yml`).
- Requires Screen Recording permission; first capture asks for it.
- Signed, notarized, updates via Sparkle.
- The overlay flow is the committed UX direction (chosen over Studio, Stage and Library-first prototypes in `prototype/`). Do not reintroduce a separate editor window. The Library and Settings are the only separate windows.

## Brand Commitments

- Name: Shiny Screenshot.
- Icon: `assets/icon.svg`. Yellow selection frame with floating toolbar is the signature look (see `assets/banner.jpg`).
- Named built-in wallpapers: Silk, Prism, Solstice, Boreal, plus a gallery of 67 backgrounds in five groups.
- Voice: short, plain, functional (see README).

## Evidence on Hand

- `assets/banner.jpg`, `assets/screenshots/` (background panel, exports on each wallpaper), `assets/previews/` rendered from real SwiftUI views via `assets/tools/render-previews.swift`.
- `prototype/index.html` (four directions), `prototype/in-place.html` (chosen flow).
- No testimonials, user counts, press or pricing exist. Do not fabricate them.

## Product Principles

1. The pasted image must look finished without extra work.
2. Stay where the user is: everything happens on the capture overlay.
3. Keyboard first; every action reachable without the mouse.
4. Get out of the way fast: capture to paste in seconds.
5. Nothing is lost: annotations stay editable after copy, in Recent and the Library.
