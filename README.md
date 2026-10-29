<p align="center">
  <img src="assets/icon.svg" width="96" height="96" alt="">
</p>

<h1 align="center">Shiny Screenshot</h1>

<p align="center">
  A macOS menu bar app for screenshots you mark up right where you take them:<br>
  select an area, draw on it, wrap it in a background, copy. No editor window.
</p>

<p align="center">
  <a href="https://github.com/przemekkkkkkkkkkkkkkkkk/shiny-screenshot/releases/latest"><img src="https://img.shields.io/github/v/release/przemekkkkkkkkkkkkkkkkk/shiny-screenshot?label=download" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-blue" alt="macOS 15+">
</p>

<img src="assets/banner.jpg" width="1200" alt="Shiny Screenshot: a yellow selection frame and floating annotation toolbar over a screenshot, with Silk wallpaper behind it.">

## Screenshots

**Your selection is the editor.** Press ⇧⌘2, drag an area, and the toolbar appears right under it: arrows, boxes, highlight, blur, numbered steps, text and pen.

**Add a background without leaving the screen.** Wallpapers, gradients, padding, roundness, shadow, and fixed sizes for social posts.

<img src="assets/screenshots/background.jpg" width="1200" alt="The Background panel next to a selection: wallpaper and gradient tiles, padding, roundness and shadow sliders, and size presets.">

**What you paste.** The same capture copied with each built-in wallpaper:

<table>
  <tr>
    <td><img src="assets/screenshots/export-silk.jpg" alt="Exported screenshot on the Silk wallpaper"></td>
    <td><img src="assets/screenshots/export-prism.jpg" alt="Exported screenshot on the Prism wallpaper"></td>
  </tr>
  <tr>
    <td align="center">Silk</td>
    <td align="center">Prism</td>
  </tr>
  <tr>
    <td><img src="assets/screenshots/export-solstice.jpg" alt="Exported screenshot on the Solstice wallpaper"></td>
    <td><img src="assets/screenshots/export-boreal.jpg" alt="Exported screenshot on the Boreal wallpaper"></td>
  </tr>
  <tr>
    <td align="center">Solstice</td>
    <td align="center">Boreal</td>
  </tr>
</table>

## Install

Download the DMG from the [latest release](https://github.com/przemekkkkkkkkkkkkkkkkk/shiny-screenshot/releases/latest) and drag Shiny Screenshot to Applications. It's signed and notarized, and updates itself through Sparkle.

## Build from source

Needs macOS 15+, Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen
open ShinyScreenshot.xcodeproj   # then Run, or:
xcodebuild -scheme ShinyScreenshot -derivedDataPath build build && open build/Build/Products/Debug/ShinyScreenshot.app
```

The first capture asks for Screen Recording permission (System Settings › Privacy & Security › Screen & System Audio Recording). Reopen the app after granting it.

## Use

| | |
|---|---|
| ⇧⌘2 | Capture an area (also in the menu bar; change it in Settings) |
| Drag, or click a window | Select |
| A R H B N T P | Arrow, rectangle, highlight, blur, numbered step, text, pen |
| Esc | Drop the tool, then close the background panel, then cancel |
| Return or ⌘C | Copy and close |
| ⌘S | Save to Desktop, or the folder picked in Settings |
| ⌘Z | Undo |

With no tool selected, drag inside the selection to move it, or drag its handles to resize. After copying, a card in the corner lets you drag the image into another app, save it, pin it above all windows, or reopen it with every annotation still editable.

Settings (menu bar icon › Settings…) holds the shortcut, save folder, open at login and update options.

## Release

`scripts/release.sh` builds, notarizes and staples the app and DMG, then writes the Sparkle `appcast.xml`. Bump the version in `project.yml` first. Publishing the DMG and `appcast.xml` as a GitHub release of `przemekkkkkkkkkkkkkkkkk/shiny-screenshot` is what installed copies check for updates.

## Tests

```sh
xcodebuild -scheme ShinyScreenshot -derivedDataPath build test
```

`prototype/` holds the throwaway HTML design prototypes. `assets/tools/` regenerates the icon, banner and screenshots; `render-previews.swift` renders the screenshots from the real SwiftUI views into `assets/previews/`, so they match the app.
