#!/bin/bash
# Sign the Ninja-built skate3.app and install it on the connected iPhone.
#
# The Xcode *generator* cannot build this project (it merges duplicate source
# basenames and drops object files), so the app is built with Ninja and signed
# here by hand instead of by Xcode's build phases.
#
# Prerequisites, both one-time and interactive:
#   1. Xcode > Settings > Accounts > sign in with your Apple ID, select your
#      team, Manage Certificates > + > Apple Development.
#      `security find-identity -v -p codesigning` must then list an identity.
#   2. iPhone connected by cable, unlocked, and "Trust This Computer" accepted.
set -euo pipefail

SKATE3_ROOT="${SKATE3_ROOT:-$HOME/skate3}"
APP="${1:-$SKATE3_ROOT/skate3recomp-dev/out/build/ios-ninja/skate3.app}"

# Your team id. skate3-setup.sh passes this in; standalone, it is read from a
# provisioning profile. NOT from the signing certificate's name - on a modern
# "Apple Development: Name (XXXXXXXXXX)" certificate that code is the
# developer's person id, not the team id.
if [ -z "${TEAM_ID:-}" ]; then
  for pdir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
              "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    [ -d "$pdir" ] || continue
    for prof in "$pdir"/*.mobileprovision; do
      [ -e "$prof" ] || continue
      tmp=$(mktemp)
      security cms -D -i "$prof" > "$tmp" 2>/dev/null \
        && TEAM_ID=$(plutil -extract TeamIdentifier.0 raw -o - "$tmp" 2>/dev/null || true)
      rm -f "$tmp"
      [ -n "${TEAM_ID:-}" ] && break 2
    done
  done
fi
[ -n "${TEAM_ID:-}" ] || { echo "Set TEAM_ID=<your 10-char Apple team id>"; exit 1; }

[ -d "$APP" ] || { echo "no app bundle at $APP - build it first"; exit 1; }

IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development|iPhone Developer/ {print $2; exit}')
if [ -z "$IDENTITY" ]; then
  echo "No code signing identity in the keychain."
  echo "Open Xcode > Settings > Accounts and create an Apple Development certificate."
  exit 1
fi
echo "signing identity: $IDENTITY"

# A development build needs a provisioning profile that names this device and
# matches the app id. Xcode mints these; reuse the newest one for this team.
# Xcode 16+ keeps profiles under UserData; older ones live in MobileDevice.
# Match on the app's own bundle id rather than just the team: a team can have
# many profiles, and installing with one whose application-identifier does not
# match the bundle is rejected on device.
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist" 2>/dev/null)
[ -n "$BUNDLE_ID" ] || { echo "could not read CFBundleIdentifier from $APP/Info.plist"; exit 1; }
echo "bundle id: $BUNDLE_ID"

now_epoch=$(date -u +%s)
PROFILE=$(ls -t "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision \
                "$HOME/Library/MobileDevice/Provisioning Profiles/"*.mobileprovision 2>/dev/null | while read -r p; do
  plist=$(security cms -D -i "$p" 2>/dev/null) || continue
  appid=$(printf '%s' "$plist" | plutil -extract Entitlements.application-identifier raw - 2>/dev/null) || continue
  [ "$appid" = "$TEAM_ID.$BUNDLE_ID" ] || continue
  # Compare expiry as epoch seconds; the raw date string does not sort usefully.
  exp=$(printf '%s' "$plist" | plutil -extract ExpirationDate raw - 2>/dev/null | cut -d. -f1)
  exp_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$exp" +%s 2>/dev/null \
           || date -j -f '%Y-%m-%d %H:%M:%S +0000' "$exp" +%s 2>/dev/null || echo 0)
  [ "$exp_epoch" -gt "$now_epoch" ] && echo "$p"
done | head -1)

if [ -z "$PROFILE" ]; then
  echo "No unexpired provisioning profile for $TEAM_ID.$BUNDLE_ID."
  echo "Mint one headlessly with a throwaway project carrying the same bundle id"
  echo "and entitlements:"
  echo "  xcodebuild -project <probe>.xcodeproj -target <probe> -sdk iphoneos \\"
  echo "    -allowProvisioningUpdates -allowProvisioningDeviceRegistration build"
  echo "(-target + -sdk, NOT -scheme/-destination: destination resolution fails when"
  echo " the phone's iOS is newer than the installed Xcode platform.)"
  exit 1
fi
echo "profile: $PROFILE"
cp "$PROFILE" "$APP/embedded.mobileprovision"

# Sign against the profile's OWN entitlements rather than the repo's file.
# Xcode normally merges the profile's baseline entitlements (application-identifier,
# team-identifier, get-task-allow) with the project's; signing by hand skips that
# merge, and an app without application-identifier is rejected at install with
# MIInstallerErrorDomain 63. The profile already carries our two kernel
# entitlements, so its dict is the complete and correct set.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
security cms -D -i "$PROFILE" > "$WORK/profile.plist" 2>/dev/null
plutil -extract Entitlements xml1 -o "$WORK/entitlements.plist" "$WORK/profile.plist"

# Nested code must be signed before the bundle that contains it, innermost
# first; signing only the .app leaves the dylib unsigned and the app is then
# rejected at install time.
for dylib in "$APP"/*.dylib; do
  [ -e "$dylib" ] || continue
  echo "signing nested: $(basename "$dylib")"
  codesign --force --sign "$IDENTITY" --timestamp=none "$dylib"
done

codesign --force --sign "$IDENTITY" \
  --entitlements "$WORK/entitlements.plist" \
  --timestamp=none --generate-entitlement-der "$APP"
codesign --verify --verbose "$APP"

# Pull the identifier by its UUID shape: device names contain spaces and digits
# ("iPhone 13 mini"), so column arithmetic picks up the wrong field.
# Match the state column exactly: a plain `grep available` also matches
# "unavailable", which yields the id of a paired-but-unreachable phone and then
# fails the install with CoreDeviceError 1000.
DEVICE=$(xcrun devicectl list devices 2>/dev/null \
  | grep -ivE 'unavailable' \
  | grep -iE 'connected|available' \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
  | head -1)
if [ -z "$DEVICE" ]; then
  echo "App signed at $APP, but no connected iPhone was found."
  echo "Connect and unlock the phone, then re-run; or drag the .app onto Xcode > Devices."
  exit 0
fi
echo "installing to $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "installed. Stage game data next:"
echo "  Finder > iPhone > Files > Skate 3  <- drop the 'game' folder in"
