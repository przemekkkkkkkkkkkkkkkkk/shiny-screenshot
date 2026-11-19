---
name: Shiny Screenshot
description: Screenshots marked up in place, on native Liquid Glass with one glowing yellow control.
colors:
  marker-yellow: "#FFD60A"
  marker-light: "#FFE14D"
  marker-deep: "#F5C400"
  marker-wash: "#FFD60A47"
  ink-on-marker: "#000000"
  screen-scrim: "#0000004D"
  rim-light: "#FFFFFF99"
  well-fill: "#0000000D"
  track-fill: "#0000000F"
  hover-fill: "#00000012"
  selected-fill: "#0000001A"
  annotate-red: "#FF3B30"
  annotate-orange: "#FF9F0A"
  annotate-green: "#34C759"
  annotate-blue: "#0A84FF"
  annotate-purple: "#BF5AF2"
typography:
  panel-title:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 600
  control-label:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13.5px"
    fontWeight: 600
  primary-label:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 600
  hint:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13.5px"
    fontWeight: 500
  body:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 400
  secondary:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  well-title:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
  tab:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "11.5px"
    fontWeight: 500
  caption:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "10.5px"
    fontWeight: 500
  value-badge:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    fontFeature: "\"tnum\""
  measurement:
    fontFamily: "SF Mono, ui-monospace, Menlo, monospace"
    fontSize: "12px"
    fontWeight: 600
rounded:
  panel: "30px"
  card: "28px"
  card-shot: "20px"
  well: "18px"
  tile-ring: "15px"
  tile: "12px"
  keycap: "6px"
  capsule: "9999px"
spacing:
  hair: "2px"
  island: "5px"
  xs: "6px"
  sm: "8px"
  md: "10px"
  well: "12px"
  panel: "14px"
  lg: "18px"
components:
  button-primary:
    backgroundColor: "{colors.marker-yellow}"
    textColor: "{colors.ink-on-marker}"
    typography: "{typography.primary-label}"
    rounded: "{rounded.capsule}"
    padding: "0 18px"
    height: "50px"
  button-primary-card:
    backgroundColor: "{colors.marker-yellow}"
    textColor: "{colors.ink-on-marker}"
    rounded: "{rounded.capsule}"
    height: "36px"
  dock-button:
    rounded: "{rounded.capsule}"
    size: "40px"
  dock-button-hover:
    backgroundColor: "{colors.hover-fill}"
    rounded: "{rounded.capsule}"
  dock-button-tool-active:
    backgroundColor: "{colors.marker-yellow}"
    textColor: "{colors.ink-on-marker}"
    rounded: "{rounded.capsule}"
    size: "40px"
  dock-button-toggle-on:
    backgroundColor: "{colors.marker-wash}"
    rounded: "{rounded.capsule}"
    height: "40px"
    padding: "0 14px"
  dock-island:
    rounded: "{rounded.capsule}"
    padding: "{spacing.island}"
  hint-pill:
    typography: "{typography.hint}"
    rounded: "{rounded.capsule}"
    padding: "0 18px"
    height: "40px"
  size-pill:
    typography: "{typography.measurement}"
    rounded: "{rounded.capsule}"
    padding: "0 10px"
    height: "26px"
  background-panel:
    rounded: "{rounded.panel}"
    width: "300px"
  well:
    backgroundColor: "{colors.well-fill}"
    rounded: "{rounded.well}"
    padding: "{spacing.well}"
  ratio-tile-selected:
    backgroundColor: "{colors.selected-fill}"
    rounded: "{rounded.tile}"
    padding: "7px 0"
  gallery-tab-track:
    backgroundColor: "{colors.track-fill}"
    typography: "{typography.tab}"
    rounded: "{rounded.capsule}"
    padding: "3px"
  value-badge:
    backgroundColor: "{colors.hover-fill}"
    typography: "{typography.value-badge}"
    rounded: "{rounded.capsule}"
    padding: "3px 0"
  corner-card:
    rounded: "{rounded.card}"
    padding: "{spacing.sm}"
    width: "300px"
---

# Design System: Shiny Screenshot

## Overview

**Creative North Star: "One Glowing Control"**

The capture overlay is native macOS Liquid Glass floating over the user's own frozen screen, with one glowing yellow control. It is generous and crafted rather than small: 40pt dock controls, a 50pt Copy button, a 300pt inspector with grouped wells, glass with a lit rim that catches light along its top edge. The screen, scrimmed at black 30%, is the backdrop; the bright rectangle the user dragged is the stage, framed in yellow crop marks.

Appearance follows the system. Glass is regular Liquid Glass on macOS 26 and later (`.regularMaterial` with a faint hairline before that), so the chrome is light on a light Mac and dark on a dark one; nothing is forced dark. Marker Yellow is the only accent colour in the chrome, and it is always lit: a gradient on the primary action, a soft yellow halo under whatever is on, a sliding yellow puck under the active tool, a yellow wash and rim on toggles. Everything else is glass, SF Symbols and system type.

What the user exports is a separate, expressive layer (wallpapers, mesh and gradient backgrounds, padding, corners, shadow, headings). The chrome stays native so the output can be the thing that shines. The Library and Settings are plain native macOS windows: system accent, standard controls, system text styles, no overlay styling.

The user rejected forced-dark smoked grey glass and small, dense shapes; this system replaces both.

**Key Characteristics:**
- Native Liquid Glass with a lit rim, following the system appearance.
- One accent, Marker Yellow, always lit (gradient, glow, puck, wash).
- Generous targets: 40pt dock controls, 50pt Copy, 300pt inspector.
- Concentric radii from the 30pt panel down to 12pt tiles; capsules everywhere else.
- Spring motion: the puck slides, the tab pill slides, the toolbar springs in.
- Library and Settings are plain native windows.

## Colors

One warm, lit yellow over system glass; every other hue in the chrome belongs to the user's ink.

### Primary
- **Marker Yellow** (#FFD60A): the selection frame and its crop marks, the window-hover outline, the active tool's puck, the selected background tile's ring and check, slider tints, hint-pill glyphs, the size pill's dot, and the middle stop of the primary gradient. Text on it is always black.
- **Marker Light** (#FFE14D) and **Marker Deep** (#F5C400): the top and bottom stops of the primary gradient (light, Marker Yellow, deep, top to bottom). Used only on the primary button (dock Copy, scrolling Start, card Copy).
- **Marker Wash** (Marker Yellow at 28%): the fill of a toggled-on control (Background), paired with a 1.5pt Marker Yellow rim. Selected ratio tiles use the same yellow at 20% inside their outline.

### Neutral
- **Screen Scrim** (black at 30%): dims the frozen screen outside the selection or hovered window.
- **Lit Rim** (white, 60% at top, 4% at the sides, 22% at the bottom, plus-lighter blend): the 1pt edge on every glass shape on macOS 26+.
- **Label-relative fills**: the system label colour at 5% (well), 6% (gallery tab track), 7% (hover, value badge), 10% (selected tile). The frontmatter records the light-appearance values; in dark appearance they invert to white at the same opacities.
- **Ink on Marker** (#000000): every glyph and label on yellow.

### Annotation inks
- **Red, Orange, Green, Blue, Purple** (frontmatter `annotate-*`), plus Marker Yellow: the six system colours the user draws with. In the chrome they appear only as the colour swatch, which glows in its own colour.

### Named Rules
**The One Lit Colour Rule.** Marker Yellow is the only accent in the chrome. Other hues appear only as ink the user draws with, or as system status (the red recording dot, orange "lost track").

**The Always Lit Rule.** Yellow never sits flat: it carries a gradient, a halo (yellow at 50%, 9pt radius, 2pt down), or a rim. A flat yellow fill reads as a sticker, not a control.

**The Solid Primary Rule.** The primary action is a solid yellow gradient, never tinted glass, because glass tints grey out in a non-key overlay window.

## Typography

**Display Font:** SF Pro (system)
**Body Font:** SF Pro (system)
**Label/Mono Font:** SF Mono for measurements only; SF Pro Rounded with tabular digits for value badges and keycaps.

**Character:** The Mac's own voice, set slightly larger and heavier than stock inspector type so the overlay reads at a glance. Semibold carries every label that names an action.

### Hierarchy
- **Panel title** (600, 16pt): "Background" at the head of the inspector.
- **Primary label** (600, 14pt, 15pt symbol): the yellow buttons.
- **Control label** (600, 13.5pt, 17pt medium symbol): titled dock buttons.
- **Hint** (500, 13.5pt, 14pt semibold yellow symbol): instruction pills.
- **Body** (400, 12.5pt): slider labels, text fields, the scrolling bar.
- **Secondary** (400, 12pt, secondary colour): the backdrop name under the panel title, the Font row.
- **Well title** (600, 12pt, secondary colour): "Size", "Text".
- **Tab** (500 at rest, 600 selected, 11.5pt): gallery group tabs.
- **Caption** (500, 10.5pt / 10pt): ratio and heading tile names, gallery section labels.
- **Value badge** (600, 11pt, SF Pro Rounded, tabular digits): slider readouts in a 7% capsule.
- **Measurement** (600, 12pt, SF Mono; "px" in 10.5pt medium secondary): the selection size pill and the loupe's coordinates.

### Named Rules
**The Mono Means Measured Rule.** SF Mono appears only where the user reads pixels: the size pill and the loupe. Everything else is SF Pro or SF Pro Rounded.

## Layout

The overlay is a full-screen canvas; chrome positions itself around the selection rather than in a grid. The dock springs in under the selection (or docks at the bottom when there is no room, reserving 84pt). Hint pills sit centred 70pt from the top. The Background inspector is a 300pt column docked to the right edge, vertically centred, capped to the screen height and scrolling only when the screen is too short. The size pill rides 36pt above the selection's top-left corner.

Rhythm is small and even inside glass and generous between pieces: 2pt between buttons in an island, 5pt island padding, 8pt between islands (10pt glass blend spacing), 10pt between wells, 12pt inside a well, 14pt panel padding, 18pt around the panel header and inside pills. The corner card is 300pt wide with 8pt padding and a 284 x 200pt shot.

### Named Rules
**The Generous Target Rule.** Dock controls are 40pt, the dock primary is 50pt, card controls 36pt, the panel's shuffle button 36pt.

## Elevation & Depth

Depth comes from glass, not from stacked shadows. Every chrome surface is Liquid Glass with a lit rim; neighbouring islands sit in one glass container so they blend and morph as a single surface. Two soft ambient shadows lift the floating pieces off the user's screen, and lit controls get a coloured halo instead of a shadow.

### Shadow Vocabulary
- **Dock lift** (black 22%, 18pt radius, 10pt down): the toolbar and scrolling start bar.
- **Panel lift** (black 22%, 24pt radius, 12pt down): the Background inspector.
- **Yellow glow** (Marker Yellow 50%, 9pt radius, 2pt down): the primary button, the active tool's puck, the selected gallery tile, the size pill's dot. Colour swatches glow in their own colour.
- **Selection glow** (Marker Yellow 60%, 5pt radius): around the 1.5pt selection outline.
- **Tab lift** (black 12%, 3pt radius, 1pt down): the sliding gallery tab pill.

### Named Rules
**The Glow, Not Shadow Rule.** An "on" control shows its state with a halo in its own colour, like a lit knob under glass. Dark drop shadows are only for lifting whole surfaces off the screen.

## Shapes

Capsules for every control, pill and island; continuous rounded rectangles for containers, nested concentrically: the 30pt inspector holds 18pt wells, which hold 12pt tiles; the 28pt corner card holds a 20pt shot at 8pt inset; gallery tiles are 12pt inside a 15pt selection ring at 3pt inset. Keycaps on the primary button are 6pt. The selection itself is square-cornered, marked by rounded 4.5pt yellow crop brackets with a dark hairline so they read on any screen. The hovered-window outline is 10pt to match macOS windows. The countdown tile is a standalone 26pt glass rectangle.

### Named Rules
**The Concentric Rule.** An inner radius is its container's radius minus the inset between them. Never put a sharper inner corner against a softer outer one at random.

## Components

### Buttons
Lit, chunky and native.
- **Shape:** capsule.
- **Primary (Copy, Start):** vertical gradient Marker Light to Marker Deep, black 14pt semibold label with a 15pt symbol, 50pt tall, 18pt sides, a 20pt keycap ("↩") in black 12% on a 6pt radius, a white 55% overlay rim, and the yellow glow. Hover scales to 1.03 on a quick spring. On the corner card the same gradient runs 36pt tall and fills the row.
- **Dock button:** 40pt minimum, 17pt medium symbol, primary-colour glyph; hover shows a 7% fill.
- **Active tool:** a Marker Yellow gradient puck with the yellow glow and a black glyph; one puck shared by all tools slides to the selected one.
- **Toggle on (Background):** yellow wash at 28% with a 1.5pt Marker Yellow rim; the glyph and title stay primary colour so they read on any glass.
- **Glass circle (shuffle, dismiss):** 36pt or 28pt interactive glass circle.

### Dock
Islands of glass capsules (tools; colour; undo, pin, save; Background) plus the Copy button, in one glass container with 8pt gaps. The colour island shows one 22pt glowing swatch at rest and opens into the six-colour palette in place on a spring, closing on a pick; the selected swatch gets a 30pt primary ring.

### Background inspector
A 300pt glass panel, 30pt radius. Fixed header (16pt title, backdrop name, shuffle circle), then the gallery and grouped **wells** (5% fill, 18pt radius, 12pt padding, optional 12pt semibold secondary title) like System Settings groups. Sliders are tinted Marker Yellow with a leading 12pt secondary symbol, a 58pt label column and a rounded value badge. Segmented pickers, the font popup and the text-shadow switch are native controls at small size.

### Gallery
A segmented track of capsule tabs (6% fill, 3pt padding) with a sliding tab pill (background colour at 75%, tab lift) that jumps the scrolling grid to a group. Tiles are 44pt tall in four columns, 12pt radius with a 12% hairline; the selected tile gets a 2pt Marker Yellow ring on 15pt, a yellow check badge, the yellow glow, and scales from 0.97 to 1.

### Tiles (ratio and heading)
Each option drawn as itself: ratio tiles draw their own aspect as a 1.5pt outline (dashed for Auto), heading tiles show an "Aa" specimen in their own type. Selected: 10% fill on a 12pt radius, and Marker Yellow on the outline (ratio) or a 1.5pt yellow rim (heading).

### Pills
- **Hint pill:** 40pt glass capsule, 18pt sides, yellow 14pt symbol and 13.5pt medium text.
- **Size pill:** 26pt glass capsule with a glowing 7pt yellow dot, SF Mono dimensions and a secondary "px".

### Selection
1.5pt Marker Yellow outline with a 5pt yellow glow; 22pt handle marks drawn as rounded yellow corner brackets (10pt arms) and edge grips (16pt), each over a black 35% hairline.

### Corner card and pins
The corner card is a 300pt glass card on 28pt with the shot leading edge to edge at 20pt, a glass status capsule and a glass dismiss circle floating on it, and a 36pt row: the yellow Copy capsule plus four glass icon capsules. Pins show a 30pt glass capsule with opacity slider and close on hover.

### Native windows
Library and Settings use standard SwiftUI and AppKit controls with the system accent and system text styles. They do not use glassChrome, Marker Yellow or the overlay's sizes.

### Motion
Every state change is a spring: the toolbar springs in (response 0.38, damping 0.82) with a scale-from-0.92 plus fade from the top; the tool puck slides (0.32 / 0.78); the palette opens (0.34 / 0.8); the Background toggle and inspector (0.4 / 0.85, inspector slides in from the trailing edge); tile selection (0.3 / 0.75); the tab pill (0.3 / 0.8); hover on the primary (0.25 / 0.7).

## Do's and Don'ts

### Do:
- **Do** use `glassChrome` for every overlay surface, so it gets Liquid Glass and the lit rim on macOS 26+ and `.regularMaterial` before.
- **Do** let the appearance follow the system.
- **Do** mark "on" with Marker Yellow plus a glow, a puck, or a wash and rim.
- **Do** keep dock controls at 40pt and the dock primary at 50pt.
- **Do** nest radii concentrically: 30 panel, 28 card, 18 wells, 12 tiles, capsules elsewhere.
- **Do** group neighbouring glass in one `GlassGroup` so it blends as one surface.
- **Do** animate state with springs, and slide a shared indicator (`matchedGeometryEffect`) rather than cross-fading.
- **Do** keep Library and Settings plain native windows.

### Don't:
- **Don't** force the dark appearance or use smoked grey glass.
- **Don't** shrink controls into dense, small instrument targets.
- **Don't** introduce a second accent colour in the chrome; other hues are user ink or system status only.
- **Don't** make the primary action tinted glass; it greys out in a non-key overlay.
- **Don't** use SF Mono outside measurements.
- **Don't** use dark drop shadows to show state; use the glow.
