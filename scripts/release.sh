#!/bin/sh
# Builds Shiny Screenshot signed with Developer ID, notarized by Apple and stapled:
# build/release/ShinyScreenshot.app, ShinyScreenshot.zip, ShinyScreenshot-<version>.dmg and the Sparkle appcast.xml.
#
# One-time setup (asks for an app-specific password from account.apple.com and keeps it in your keychain):
#   xcrun notarytool store-credentials shiny-notary --apple-id <your Apple ID> --team-id Y9YVY93347
# and dmgbuild, which lays out the disk image window:
#   brew install pipx && pipx install dmgbuild
# The Sparkle update key is in the keychain too (account shiny-screenshot; its public half is SUPublicEDKey in project.yml).
# Back it up with: build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account shiny-screenshot -x <file>
#
# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml first: Sparkle compares the build number.
#
# NOTARIZE_ONLY=1 skips the build and notarizes the app already in build/release.
set -eu
cd "$(dirname "$0")/.."
ARCHIVE=build/ShinyScreenshot.xcarchive
OUT=build/release
PROFILE=${NOTARY_PROFILE:-shiny-notary}

# Submits $1 to Apple and waits; on rejection prints Apple's log and stops.
notarize() {
  result=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --timeout 2h --output-format json) || true
  echo "$result"
  id=$(echo "$result" | plutil -extract id raw -o - -)
  status=$(echo "$result" | plutil -extract status raw -o - -)
  if [ "$status" != "Accepted" ]; then
    echo "Notarization of $1: $status. Apple's log:" >&2
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2
    exit 1
  fi
}

if [ -z "${NOTARIZE_ONLY:-}" ]; then
  rm -rf "$ARCHIVE" "$OUT"
  xcodegen generate
  xcodebuild -project ShinyScreenshot.xcodeproj -scheme ShinyScreenshot -configuration Release \
    -archivePath "$ARCHIVE" -clonedSourcePackagesDirPath build/SourcePackages -allowProvisioningUpdates archive
  cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>Y9YVY93347</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions.plist \
    -exportPath "$OUT" -allowProvisioningUpdates
fi

ditto -c -k --keepParent "$OUT/ShinyScreenshot.app" "$OUT/upload.zip"
notarize "$OUT/upload.zip"
rm "$OUT/upload.zip"
xcrun stapler staple "$OUT/ShinyScreenshot.app"
spctl --assess --type execute --verbose=2 "$OUT/ShinyScreenshot.app"
ditto -c -k --keepParent "$OUT/ShinyScreenshot.app" "$OUT/ShinyScreenshot.zip"

# Disk image: the app next to an Applications shortcut to drag it onto, over the background and layout
# in assets/dmg. Notarized and stapled too, so it opens cleanly after download.
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$OUT/ShinyScreenshot.app/Contents/Info.plist")
DMG="$OUT/ShinyScreenshot-$VERSION.dmg"
rm -f "$DMG"
dmgbuild -s assets/dmg/settings.py -D app="$OUT/ShinyScreenshot.app" "Shiny Screenshot" "$DMG"
# Signs the image too once a Developer ID certificate is in this Mac's keychain (Xcode › Settings › Accounts › Manage Certificates).
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  codesign --sign "Developer ID Application" --timestamp "$DMG"
fi
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# Sparkle feed for this release. Installed apps read it from the latest GitHub release (SUFeedURL in project.yml).
rm -rf build/appcast
mkdir -p build/appcast
cp "$DMG" build/appcast/
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast --account shiny-screenshot \
  --download-url-prefix "https://github.com/przemekkkkkkkkkkkkkkkkk/shiny-screenshot/releases/download/v$VERSION/" \
  -o "$OUT/appcast.xml" build/appcast
rm -rf build/appcast
echo "Ready: $OUT/ShinyScreenshot.zip, $DMG and $OUT/appcast.xml"
echo "Publish: gh release create v$VERSION \"$DMG\" $OUT/appcast.xml -R przemekkkkkkkkkkkkkkkkk/shiny-screenshot"
