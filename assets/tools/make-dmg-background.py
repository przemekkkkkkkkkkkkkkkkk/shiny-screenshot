#!/usr/bin/env python3
"""Draws the disk image window background: assets/dmg/background.png and background@2x.png (660×420 pt).
The Silk wallpaper, marked up the way Shiny Screenshot marks up a capture: a yellow selection around the app
and an arrow to Applications. Icon centres must match icon_locations in assets/dmg/settings.py.
Uses development-only Pillow; run once after changing the design.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/dmg'
K = 2  # drawn at 2×, then scaled down for 1×
W, H = 660, 420
APP, APPS = (170, 205), (490, 205)
YELLOW = (255, 214, 10)


def font(size, weight):
    f = ImageFont.truetype('/System/Library/Fonts/SFNS.ttf', size * K)
    f.set_variation_by_name(weight)
    return f


def s(*v):
    return tuple(round(x * K) for x in v)


wall = Image.open(ROOT / 'ShinyScreenshot/Assets.xcassets/Wallpapers/Silk.imageset/Silk.jpg').convert('RGB')
im = ImageOps.fit(wall, s(W, H), method=Image.Resampling.LANCZOS, centering=(0.5, 0.45)).convert('RGBA')

# Deep indigo at the top for the title, easing off to a mid tone behind the icon labels.
# Finder draws labels black in Light Mode and white in Dark Mode; a mid tone keeps both readable.
shade = Image.new('RGBA', im.size)
d = ImageDraw.Draw(shade)
for y in range(im.height):
    t = y / im.height
    a = 205 - 185 * min(1, t / 0.5)
    d.line([(0, y), (im.width, y)], fill=(14, 12, 48, round(a)))
im = Image.alpha_composite(im, shade)

# Soft glow behind each icon.
glow = Image.new('RGBA', im.size)
d = ImageDraw.Draw(glow)
# The wallpaper is darker on the left, so the app gets more.
for (cx, cy), alpha in ((APP, 255), (APPS, 90)):
    d.ellipse(s(cx - 100, cy - 70, cx + 100, cy + 110), fill=(175, 185, 255, alpha))
im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(40 * K)))

marks = Image.new('RGBA', im.size)
d = ImageDraw.Draw(marks)

# The selection: frame, eight handles and a size tag, as in the app.
x0, y0, x1, y1 = APP[0] - 84, APP[1] - 78, APP[0] + 84, APP[1] + 104
d.rectangle(s(x0, y0, x1, y1), outline=YELLOW, width=round(1.5 * K))
for hx in (x0, (x0 + x1) / 2, x1):
    for hy in (y0, (y0 + y1) / 2, y1):
        if (hx, hy) != ((x0 + x1) / 2, (y0 + y1) / 2):
            d.rounded_rectangle(s(hx - 5, hy - 5, hx + 5, hy + 5), radius=3 * K, fill=YELLOW)
tag = font(11, 'Semibold')
d.rounded_rectangle(s(x0, y0 - 26, x0 + 74, y0 - 7), radius=5 * K, fill=YELLOW)
d.text(s(x0 + 37, y0 - 16.5), '⇧⌘2', font=tag, fill=(20, 20, 20), anchor='mm')

# The arrow, bending over the gap like one drawn with the arrow tool.
def bezier(p0, p1, p2, n=60):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in (i / n for i in range(n + 1))]

start, ctrl, end = (APP[0] + 108, APP[1] - 20), (330, APP[1] - 92), (APPS[0] - 92, APPS[1] - 24)
curve = [s(*p) for p in bezier(start, ctrl, end)]
d.line(curve, fill=YELLOW, width=round(5 * K), joint='curve')
d.ellipse(s(start[0] - 2.5, start[1] - 2.5, start[0] + 2.5, start[1] + 2.5), fill=YELLOW)
(ax, ay), (bx, by) = curve[-6], curve[-1]
length = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
ux, uy = (bx - ax) / length, (by - ay) / length
head = 17 * K
tip = (bx + ux * head * 0.45, by + uy * head * 0.45)
d.polygon([tip,
           (tip[0] - ux * head + uy * head * 0.62, tip[1] - uy * head - ux * head * 0.62),
           (tip[0] - ux * head - uy * head * 0.62, tip[1] - uy * head + ux * head * 0.62)], fill=YELLOW)

shadow = Image.new('RGBA', im.size, (0, 0, 0, 0))
shadow.putalpha(marks.getchannel('A').point(lambda a: a * 0.45))
im = Image.alpha_composite(im, shadow.filter(ImageFilter.GaussianBlur(4 * K)).transform(
    im.size, Image.Transform.AFFINE, (1, 0, 0, 0, 1, -2 * K)))
im = Image.alpha_composite(im, marks)

d = ImageDraw.Draw(im)
d.text(s(W / 2, 40), 'Shiny Screenshot', font=font(26, 'Bold'), fill='white', anchor='mm')
d.text(s(W / 2, 68), 'Drag the app onto Applications to install', font=font(13, 'Medium'),
       fill=(255, 255, 255, 200), anchor='mm')

OUT.mkdir(exist_ok=True)
im = im.convert('RGB')
im.save(OUT / 'background@2x.png', dpi=(144, 144))
im.resize((W, H), Image.Resampling.LANCZOS).save(OUT / 'background.png', dpi=(72, 72))

# Mean luminance behind the two labels (relative, 0–1): near 0.18 gives black and white text similar contrast.
def lum(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
for name, (cx, cy) in (('app', APP), ('Applications', APPS)):
    box = im.crop(s(cx - 55, cy + 70, cx + 55, cy + 88)).resize((1, 1), Image.Resampling.BOX).getpixel((0, 0))
    print(name, 'label background luminance', round(0.2126 * lum(box[0]) + 0.7152 * lum(box[1]) + 0.0722 * lum(box[2]), 3))
