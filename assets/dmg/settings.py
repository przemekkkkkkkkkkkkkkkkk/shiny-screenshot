# dmgbuild settings for the release disk image, used by scripts/release.sh from the repository root:
#   dmgbuild -s assets/dmg/settings.py -D app=build/release/ShinyScreenshot.app "Shiny Screenshot" out.dmg
# Icon centres match APP and APPS in assets/tools/make-dmg-background.py, which draws the background.
files = [(defines['app'], 'Shiny Screenshot.app')]  # noqa: F821
symlinks = {'Applications': '/Applications'}
icon_locations = {'Shiny Screenshot.app': (170, 205), 'Applications': (490, 205)}
background = 'assets/dmg/background.png'  # dmgbuild adds background@2x.png for Retina
# The window frame includes Finder's title bar (28 pt, 32 on macOS 26) on top of the 660×420 background.
window_rect = ((200, 120), (660, 448))
show_status_bar = False
icon_size = 128
text_size = 13
format = 'UDZO'
filesystem = 'HFS+'
