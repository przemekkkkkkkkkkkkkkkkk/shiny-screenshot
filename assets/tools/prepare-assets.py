#!/usr/bin/env python3
"""Build catalog PNGs and JPEGs with Pillow + rsvg-convert (development tools only).
Run: python3 assets/tools/prepare-assets.py [Silk.png Prism.png Solstice.png Boreal.png]
Without inputs, rebuild icons and previews using the existing catalog wallpapers.
"""
import json
from pathlib import Path
import subprocess
import sys
from PIL import Image, ImageCms, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'ShinyScreenshot/Assets.xcassets'
PREVIEWS = ROOT / 'assets/previews'
SRGB = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
NAMES = ['Silk', 'Prism', 'Solstice', 'Boreal']
FONT = '/System/Library/Fonts/SFNS.ttf'

def manifest(folder, **contents):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'Contents.json').write_text(json.dumps({**contents, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')

def save_png(im, path):
    im.save(path, icc_profile=SRGB, optimize=True)

PREVIEWS.mkdir(parents=True, exist_ok=True)
manifest(CATALOG)
subprocess.run(['rsvg-convert', '-w', '2048', '-h', '2048', '-o', str(PREVIEWS/'app-icon-1024.png'), str(ROOT/'assets/icon.svg')], check=True)
icon = Image.open(PREVIEWS/'app-icon-1024.png').convert('RGBA').resize((1024,1024), Image.Resampling.LANCZOS)
save_png(icon, PREVIEWS/'app-icon-1024.png')
# Thicken the marquee at small sizes so it remains yellow rather than antialiasing away.
small_svg = (ROOT/'assets/icon.svg').read_text().replace('stroke-width="24"', 'stroke-width="48"')
small_source = PREVIEWS/'icon-optical-small.svg'
small_source.write_text(small_svg)
subprocess.run(['rsvg-convert','-w','1024','-h','1024','-o',str(PREVIEWS/'icon-optical-small.png'),str(small_source)],check=True)
small_icon = Image.open(PREVIEWS/'icon-optical-small.png').convert('RGBA')
small_source.unlink()
(PREVIEWS/'icon-optical-small.png').unlink()
items = []
for size in [16,32,128,256,512]:
    for scale in [1,2]:
        name = f'icon_{size}x{size}@{scale}x.png'
        save_png((small_icon if size*scale<=32 else icon).resize((size*scale,size*scale), Image.Resampling.LANCZOS), CATALOG/'AppIcon.appiconset'/name)
        items.append({'idiom':'mac','size':f'{size}x{size}','scale':f'{scale}x','filename':name})
manifest(CATALOG/'AppIcon.appiconset', images=items)
manifest(CATALOG/'MenuBarIcon.imageset', images=[{'idiom':'mac','filename':'MenuBarIcon.pdf'}], properties={'preserves-vector-representation':True,'template-rendering-intent':'template'})
subprocess.run(['rsvg-convert','-f','pdf','-o',str(CATALOG/'MenuBarIcon.imageset/MenuBarIcon.pdf'),str(ROOT/'assets/tools/menu-bar-icon.svg')],check=True)
manifest(CATALOG/'Wallpapers')
if len(sys.argv)>1:
    assert len(sys.argv)==5, 'Provide all four wallpaper source paths in Silk, Prism, Solstice, Boreal order.'
    for name, source in zip(NAMES, sys.argv[1:]):
        folder=CATALOG/f'Wallpapers/{name}.imageset'
        manifest(folder, images=[{'idiom':'universal','filename':name+'.jpg'}])
        art=ImageOps.fit(Image.open(source).convert('RGB'),(2880,1800),method=Image.Resampling.LANCZOS)
        art.save(folder/(name+'.jpg'),quality=85,optimize=True,progressive=True,icc_profile=SRGB)
        assert (folder/(name+'.jpg')).stat().st_size < 1_500_000

sheet=Image.new('RGB',(1240,800),'#f1f1f5');d=ImageDraw.Draw(sheet)
font=ImageFont.truetype(FONT,22)
d.text((30,24),'Shiny Screenshot · icon scale checks',font=font,fill='#252537')
x=32
for size in [16,32,64,128,512]:
    small=(small_icon if size<=32 else icon).resize((size,size),Image.Resampling.LANCZOS)
    sheet.paste(small,(x,95),small)
    d.text((x,95+max(size,128)+15),str(size)+' px',font=font,fill='#252537')
    if size<=64:
        zoom=small.resize((128,128),Image.Resampling.NEAREST)
        sheet.paste(zoom,(x,330),zoom)
    x+=max(size,128)+32
# Actual status icon at 1x/2x on both menu bar appearances.
for scale in [1,2]:
    temp=PREVIEWS/f'menu-bar-{18*scale}.png'
    subprocess.run(['rsvg-convert','-w',str(18*scale),'-h',str(18*scale),'-o',str(temp),str(ROOT/'assets/tools/menu-bar-icon.svg')],check=True)
    mark=Image.open(temp).convert('RGBA')
    save_png(mark,temp)
    for row,bg in enumerate(['#f5f5f7','#24242a']):
        px=32+(scale-1)*170;py=560+row*70
        d.rounded_rectangle((px,py,px+140,py+52),radius=10,fill=bg)
        if row:
            mark=Image.merge('RGBA',(Image.new('L',mark.size,255),)*3+(mark.getchannel('A'),))
        sheet.paste(mark,(px+16,py+(52-mark.height)//2),mark)
d.text((400,590),'Menu bar · 18 pt / 1× + 2×',font=font,fill='#252537')
save_png(sheet,PREVIEWS/'icon-contact-sheet.png')

sheet=Image.new('RGB',(1440,1000),'#16161d');d=ImageDraw.Draw(sheet)
for i,name in enumerate(NAMES):
    art=Image.open(CATALOG/f'Wallpapers/{name}.imageset/{name}.jpg')
    art=ImageOps.fit(art,(720,450),method=Image.Resampling.LANCZOS)
    x=i%2*720;y=i//2*500
    sheet.paste(art,(x,y));d.text((x+24,y+460),name,font=font,fill='white')
save_png(sheet,PREVIEWS/'wallpapers.png')
print('Prepared ten app icons, vector menu icon, wallpapers and PNG previews.')
