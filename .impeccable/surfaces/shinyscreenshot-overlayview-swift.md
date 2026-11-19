---
version: 1
slug: "shinyscreenshot-overlayview-swift"
primary_target: "ShinyScreenshot/OverlayView.swift"
related_targets: ["ShinyScreenshot/Panels.swift","ShinyScreenshot/Scrolling.swift"]
---

# Capture overlay

Mode: Operate. Surfaces: capture overlay and toolbar, Background panel, label bar, hint pills, corner card, pins, scrolling HUD. Library and Settings stay native windows and inherit the system's Liquid Glass.

## Direction contract

THESIS: The overlay is native macOS Liquid Glass floating over your own frozen screen; refuses the opaque smoked HUD bar every capture tool ships.
OWN-WORLD: Regular Liquid Glass in dark appearance (smoked panel fallback before macOS 26), capsule clusters and 26pt concentric panels, SF Pro and SF Symbols, Marker Yellow #FFD60A as the single solid "on" and primary colour, yellow selection frame and mono size badge kept as the signature.
STORY: The user sees their own screen through the chrome, picks a tool, marks up, wraps a background and copies, never leaving the screen.
FIRST VIEWPORT: Dimmed screen, yellow selection with handles and badge; under it one bar of five glass capsules (tools, colours, undo/pin/save, Background, solid yellow Copy) blending in one GlassEffectContainer; Background panel as a 270pt glass sheet docked right.
FORM: Liquid Glass, pinned by the user in words ("Still far from the latest Liquid Glass concepts") after a rolled hand (seed:419a14f4e5c6ff37; Instant Print assigned, Framing Shop, Factory Catalog, canon) was rejected; the first-surface experience is the user's earlier pinned "In place" flow (no editor window; mark up, add a background and copy on the overlay). The pin overrides the roll. seed: none (pinned)
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
