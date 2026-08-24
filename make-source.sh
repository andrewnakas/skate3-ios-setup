#!/bin/bash
# Generate the AltStore/SideStore source manifest for a release.
#
#   ./make-source.sh <ipa-path> <download-url> [output.json]
#
# The manifest is what AltStore reads when someone adds the source; it needs
# the version, size and a URL it can fetch the .ipa from. Point it at a GitHub
# release asset.
set -euo pipefail

IPA="${1:?usage: make-source.sh <ipa-path> <download-url> [out.json]}"
URL="${2:?usage: make-source.sh <ipa-path> <download-url> [out.json]}"
OUT="${3:-$HOME/skate3/skate3-ios-setup/source.json}"

[ -f "$IPA" ] || { echo "no ipa at $IPA" >&2; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
unzip -qq -o "$IPA" -d "$WORK"
APP=$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "no .app inside the ipa" >&2; exit 1; }

PLIST="$APP/Info.plist"
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")
MIN_OS=$(plutil -extract MinimumOSVersion raw -o - "$PLIST" 2>/dev/null || echo "16.0")
SIZE=$(stat -f%z "$IPA")
SHA=$(shasum -a 256 "$IPA" | cut -d' ' -f1)
DATE=$(date -u +%Y-%m-%d)

cat > "$OUT" <<JSON
{
  "name": "Skate 3 Recompiled",
  "identifier": "com.skate3recomp.source",
  "apps": [
    {
      "name": "Skate 3",
      "bundleIdentifier": "$BUNDLE_ID",
      "developerName": "Skate 3 Recompiled",
      "subtitle": "Bring your own copy of the game.",
      "localizedDescription": "A static recompilation of Skate 3 for iOS, rendering through Vulkan on MoltenVK.\\n\\nYOU MUST SUPPLY THE GAME. This app contains no game content. After installing, copy your own game files into the app's Documents folder over Finder or the Files app. Without them it will not start.\\n\\nOn-screen touch controls appear when no controller is attached; MFi and Bluetooth controllers are picked up automatically.\\n\\nRuns at 60fps on an iPhone 13 mini. Requires iOS $MIN_OS or later.",
      "iconURL": "",
      "tintColor": "1F1F1F",
      "category": "games",
      "screenshots": [],
      "versions": [
        {
          "version": "$VERSION",
          "date": "$DATE",
          "size": $SIZE,
          "downloadURL": "$URL",
          "minOSVersion": "$MIN_OS",
          "localizedDescription": "Sustained 60fps, on-screen touch controls, and no game content in the bundle."
        }
      ],
      "appPermissions": { "entitlements": [], "privacy": {} }
    }
  ],
  "news": []
}
JSON

python3 -c "import json,sys; json.load(open('$OUT')); print('valid JSON')"
echo "  $OUT"
echo "  version $VERSION, $(du -h "$IPA" | cut -f1), sha256 $SHA"
echo
echo "  Publish it, then people add the raw URL as a source in AltStore/SideStore."
