#!/bin/bash
# Package a built skate3.app as an UNSIGNED .ipa for sideloading.
#
# The signature and provisioning profile are deliberately stripped: whoever
# installs this re-signs it with their own Apple ID (AltStore, SideStore,
# Sideloadly all do this), and a leftover signature from someone else's
# certificate only gets in the way.
#
#   ./make-ipa.sh [path/to/skate3.app] [output.ipa]
#
# The .app must contain no game content. This script checks, and refuses if it
# finds any - a build that staged the title-update patches would otherwise turn
# into a release that redistributes them.
set -euo pipefail

APP="${1:-$HOME/skate3/skate3recomp-dev/out/build/ios-ninja/skate3.app}"
OUT="${2:-$HOME/skate3/skate3.ipa}"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$APP" ] || die "no app bundle at $APP - build it first"

# --- refuse to package game content -----------------------------------------
# The whole distribution model rests on this: the binary is a translation of
# code the player already owns, and the player supplies the data. Shipping any
# of the publisher's files inside the archive breaks that, so it is a hard
# failure rather than a warning.
say "Checking for game content"
FOUND=$(find "$APP" \( -iname '*.xex' -o -iname '*.xexp' -o -iname '*.iso' \
                    -o -iname 'TU_*' -o -iname '*.upd' \) -print 2>/dev/null || true)
if [ -n "$FOUND" ]; then
  echo "$FOUND" | sed 's/^/    /'
  die "game content found in the bundle. Rebuild - the title-update patches
     must not be staged into the app; they are read at runtime from the game
     folder the player supplies."
fi
if [ -d "$APP/game" ]; then
  die "the bundle has a game/ directory. Remove it and rebuild."
fi
printf '  ok  no game content\n'

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

say "Staging Payload/"
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
STAGED="$WORK/Payload/$(basename "$APP")"

# Strip signing material. Whoever sideloads this signs it themselves; leaving
# a foreign signature and provisioning profile in place just makes the tools
# work around them.
say "Stripping signature and provisioning profile"
rm -rf "$STAGED/_CodeSignature"
rm -f  "$STAGED/embedded.mobileprovision"
find "$STAGED" -name '*.dylib' -exec codesign --remove-signature {} \; 2>/dev/null || true
codesign --remove-signature "$STAGED" 2>/dev/null || true

# Apple's own tooling ignores this, but some sideload paths read it.
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - "$STAGED/Info.plist" 2>/dev/null || echo "?")
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$STAGED/Info.plist" 2>/dev/null || echo "?")

say "Zipping"
rm -f "$OUT"
( cd "$WORK" && zip -qry "$OUT" Payload )
[ -f "$OUT" ] || die "zip produced nothing"

SIZE=$(du -h "$OUT" | cut -f1)
SHA=$(shasum -a 256 "$OUT" | cut -d' ' -f1)

cat <<DONE

  $OUT
  bundle    $BUNDLE_ID
  version   $VERSION
  size      $SIZE
  sha256    $SHA

  Unsigned: whoever installs it re-signs with their own Apple ID.
  The game itself is not in here - players supply their own copy.

DONE
