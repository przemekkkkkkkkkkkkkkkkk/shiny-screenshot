#!/usr/bin/env python3
"""Create a fictional capture subject and compose the hero around actual app renders.
Run once before render-previews.swift, then again afterwards to compose the banner.
Uses development-only Pillow; no app dependencies.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps, ImageCms

ROOT=Path(__file__).resolve().parents[2]
PREVIEWS=ROOT/'assets/previews'
SRGB=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
FONT='/System/Library/Fonts/SFNS.ttf'
def font(size): return ImageFont.truetype(FONT,size)
def text(d,xy,value,size,fill): d.text(xy,value,font=font(size),fill=fill)
wall=Image.open(ROOT/'ShinyScreenshot/Assets.xcassets/Wallpapers/Silk.imageset/Silk.jpg').convert('RGB')
# Synthetic neutral app subject, rendered at 2× for a 1000×680 pt capture.
im=ImageOps.fit(wall,(2000,1360),method=Image.Resampling.LANCZOS)
d=ImageDraw.Draw(im)
d.rounded_rectangle((210,160,1790,1190),radius=30,fill='#f8f8fa')
d.rounded_rectangle((210,160,1790,250),radius=30,fill='#ededf1')
d.rectangle((210,215,1790,250),fill='#ededf1')
for x,c in [(250,'#ff6058'),(290,'#febc2e'),(330,'#28c840')]:d.ellipse((x,194,x+22,216),fill=c)
text(d,(840,188),'Field notes',28,'#757580')
d.rectangle((210,250,500,1190),fill='#eeeeF3')
text(d,(255,310),'WORKSPACE',22,'#8c8c97')
for i,label in enumerate(['Overview','Ideas','Launch notes','Archive']):
 y=380+i*74
 if i==2:d.rounded_rectangle((232,y-10,477,y+46),radius=12,fill='#dddde8')
 text(d,(260,y),label,26,'#363643' if i==2 else '#777783')
text(d,(575,308),'Launch notes',52,'#242432')
text(d,(578,390),'A few things worth sharing.',28,'#8b8b96')
d.line((578,462,1660,462),fill='#e1e1e9',width=2)
text(d,(578,510),'Small details. Better days.',36,'#30303e')
text(d,(578,577),'A place for the ideas we want to keep.',28,'#777783')
for i,(title,sub) in enumerate([('A clearer first impression','Give the useful things room to breathe.'),('Ready to share','A little polish goes a long way.'),('Keep the good bits','Save the moments that move work forward.')]):
 y=680+i*130
 d.rounded_rectangle((578,y+7,608,y+37),radius=8,outline='#b1b1c0',width=3)
 text(d,(640,y),title,30,'#414150');text(d,(640,y+46),sub,25,'#92929d')
im.save(PREVIEWS/'sample-screen.png',icc_profile=SRGB)

if (PREVIEWS/'in-place.png').exists():
 # Deliberate editorial hero in the product's indigo, yellow and mesh palette.
 banner=Image.new('RGB',(2400,1200),'#151522');d=ImageDraw.Draw(banner)
 # Subtle ambient backdrop behind the app demonstration.
 glow=Image.new('RGBA',banner.size);g=ImageDraw.Draw(glow)
 g.ellipse((1050,-100,2500,1400),fill=(83,75,176,65));glow=glow.filter(ImageFilter.GaussianBlur(170))
 banner=Image.alpha_composite(banner.convert('RGBA'),glow);d=ImageDraw.Draw(banner)
 icon=Image.open(PREVIEWS/'app-icon-1024.png').resize((108,108),Image.Resampling.LANCZOS)
 banner.alpha_composite(icon,(82,76));text(d,(202,112),'Shiny Screenshot',34,'#f1f0f7')
 text(d,(108,350),'Capture.',100,'#ffffff')
 text(d,(108,472),'Mark up.',100,'#ffffff')
 text(d,(108,594),'In place.',100,'#ffd60a')
 text(d,(114,752),'Your selection is the editor.',32,'#aba9bf')
 d.rounded_rectangle((110,930,284,1006),radius=18,fill='#28283c',outline='#44435b',width=2)
 text(d,(136,944),'⇧ ⌘ 2',38,'#f7f6fa')
 text(d,(110,1047),'Made for macOS',25,'#8b889f')
 demo=Image.open(PREVIEWS/'in-place.png').convert('RGBA').resize((1450,986),Image.Resampling.LANCZOS)
 mask=Image.new('L',demo.size);ImageDraw.Draw(mask).rounded_rectangle((0,0,1449,985),radius=30,fill=255)
 shadow=Image.new('RGBA',banner.size);sh=ImageDraw.Draw(shadow)
 sh.rounded_rectangle((830,142,2280,1128),radius=40,fill=(0,0,0,160));shadow=shadow.filter(ImageFilter.GaussianBlur(35))
 banner=Image.alpha_composite(banner,shadow)
 banner.paste(demo,(830,106),mask)
 d=ImageDraw.Draw(banner);d.rounded_rectangle((830,106,2279,1091),radius=30,outline='#ffffff25',width=2)
 banner.convert('RGB').save(ROOT/'assets/banner.jpg',quality=90,optimize=True,progressive=True,icc_profile=SRGB)
 banner.resize((1200,600),Image.Resampling.LANCZOS).convert('RGB').save(PREVIEWS/'banner.png',icc_profile=SRGB)
 print('Created 2400×1200 README banner and PNG preview using the actual SwiftUI capture overlay.')
else:
 print('Created sample-screen.png; run the native renderer next, then rerun this script.')
