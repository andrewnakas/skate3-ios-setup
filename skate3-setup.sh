#!/bin/bash
# Build Skate 3 recomp for iOS from your own disc image and install it on your
# own iPhone.
#
# This script ships NO game code. It orchestrates tools on your Mac: it reads
# the disc image YOU supply, recompiles it locally, builds the app, signs it
# with YOUR Apple ID, and installs it to YOUR device. Nothing derived from the
# game leaves this machine.
#
#   ./skate3-setup.sh --iso ~/Downloads/skate3.iso --title-update ~/Downloads/TU_...
#
# Every step is skippable and resumable: re-running after a failure picks up
# where it stopped rather than redoing the expensive parts.
set -uo pipefail

# --- defaults ---------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SKATE3_ROOT:-$HOME/skate3}"
# Helper scripts ship alongside this one; fall back to ROOT for older layouts.
helper() {
  if [ -x "$HERE/$1" ]; then echo "$HERE/$1"
  elif [ -x "$ROOT/$1" ]; then echo "$ROOT/$1"
  fi
}
SRC="$ROOT/skate3recomp-dev"
GAME_DIR="$ROOT/game"
BUILD_DIR="$SRC/out/build/ios-ninja"
MVK_DIR="$ROOT/moltenvk-ios"
TOOLS_DIR="$ROOT/.setup-tools"
ISO=""
TITLE_UPDATE=""
TEAM_ID="${TEAM_ID:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
JOBS=""
SKIP_INSTALL=0
MVK_VERSION="v1.4.2"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
usage: skate3-setup.sh [options]

  --iso PATH             Your Skate 3 disc image (required on first run)
  --title-update PATH    The title update package (required on first run)
  --team-id ID           Apple Developer Team ID (10 chars). Auto-detected if
                         you have exactly one signing identity.
  --bundle-id ID         App bundle id (default com.<teamid-lower>.skate3)
  --jobs N               Parallel compile jobs (default: picked from RAM)
  --no-install           Build and sign only; do not touch a device
  -h, --help             This message

You supply the disc image. This tool never downloads game content.
USAGE
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --iso) ISO="${2:?}"; shift 2 ;;
    --title-update) TITLE_UPDATE="${2:?}"; shift 2 ;;
    --team-id) TEAM_ID="${2:?}"; shift 2 ;;
    --bundle-id) BUNDLE_ID="${2:?}"; shift 2 ;;
    --jobs) JOBS="${2:?}"; shift 2 ;;
    --no-install) SKIP_INSTALL=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
say "Checking prerequisites"

[ "$(uname -s)" = "Darwin" ] || die "This builds an iOS app, which requires macOS."

# Full Xcode, not just the Command Line Tools: the iOS SDK ships only with Xcode.
XCODE_PATH=$(xcode-select -p 2>/dev/null || true)
case "$XCODE_PATH" in
  *CommandLineTools*|"")
    die "Xcode is required (the Command Line Tools alone have no iOS SDK).
     Install Xcode from the App Store, then run:
       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
esac
xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1 \
  || die "The iOS SDK is missing. Open Xcode once and let it finish installing components."
ok "Xcode at $XCODE_PATH"

for tool in cmake ninja git; do
  command -v "$tool" >/dev/null 2>&1 \
    || die "$tool not found. Install it with:  brew install $tool"
done
ok "cmake $(cmake --version | head -1 | awk '{print $3}'), ninja, git"

[ -d "$SRC" ] || die "Source tree not found at $SRC
     Clone it first, or set SKATE3_ROOT to the directory holding skate3recomp-dev."
ok "source tree at $SRC"

# Pick a job count from RAM. The recompiled translation units are enormous
# (hundreds of MB of generated C++); the default parallelism will wedge a
# small machine. ~2.5 GB per clang is the observed high-water mark.
if [ -z "$JOBS" ]; then
  ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  JOBS=$(( ram_gb / 3 ))
  [ "$JOBS" -lt 1 ] && JOBS=1
  cores=$(sysctl -n hw.ncpu)
  [ "$JOBS" -gt "$cores" ] && JOBS=$cores
  ok "${ram_gb}GB RAM detected, using -j$JOBS"
fi

# Disk: extracted game data is ~6 GB, generated sources ~300 MB, build ~2 GB.
avail_gb=$(df -g "$ROOT" | awk 'NR==2 {print $4}')
if [ "${avail_gb:-0}" -lt 12 ]; then
  warn "only ${avail_gb}GB free on the volume holding $ROOT; ~12GB is recommended"
fi

# ---------------------------------------------------------------------------
# 2. Game data - extracted from YOUR disc image
# ---------------------------------------------------------------------------
say "Preparing game data"

if [ -d "$GAME_DIR" ] && [ -n "$(ls -A "$GAME_DIR" 2>/dev/null)" ]; then
  ok "game data already present at $GAME_DIR ($(du -sh "$GAME_DIR" | cut -f1))"
else
  [ -n "$ISO" ] || die "No game data yet, so --iso is required.
     Supply the disc image dumped from your own copy of the game."
  [ -f "$ISO" ] || die "disc image not found: $ISO"

  # extract-xiso is an open-source Xbox disc tool; it contains no game content.
  XISO="$TOOLS_DIR/extract-xiso/build/extract-xiso"
  if [ ! -x "$XISO" ]; then
    say "Building extract-xiso (open-source disc extractor)"
    mkdir -p "$TOOLS_DIR"
    [ -d "$TOOLS_DIR/extract-xiso" ] \
      || git clone --depth 1 https://github.com/XboxDev/extract-xiso.git "$TOOLS_DIR/extract-xiso" \
      || die "could not clone extract-xiso"
    cmake -S "$TOOLS_DIR/extract-xiso" -B "$TOOLS_DIR/extract-xiso/build" \
          -DCMAKE_BUILD_TYPE=Release >/dev/null \
      && cmake --build "$TOOLS_DIR/extract-xiso/build" >/dev/null \
      || die "extract-xiso failed to build"
    ok "extract-xiso built"
  fi

  say "Extracting $(basename "$ISO") - this takes a few minutes"
  mkdir -p "$GAME_DIR"
  ( cd "$GAME_DIR" && "$XISO" -x "$ISO" ) || die "extraction failed"

  # extract-xiso nests its output in a directory named after the image; the
  # build wants the game root itself.
  if [ ! -e "$GAME_DIR/default.xex" ]; then
    nested=$(find "$GAME_DIR" -maxdepth 2 -name default.xex -print -quit 2>/dev/null)
    if [ -n "$nested" ]; then
      nested_dir=$(dirname "$nested")
      say "Flattening $(basename "$nested_dir")/ into the game root"
      # Move contents up, including dotfiles, then drop the empty shell.
      (shopt -s dotglob; mv "$nested_dir"/* "$GAME_DIR"/) && rmdir "$nested_dir"
    fi
  fi
  [ -e "$GAME_DIR/default.xex" ] \
    || die "no default.xex under $GAME_DIR - is that image really Skate 3?"
  ok "game data extracted ($(du -sh "$GAME_DIR" | cut -f1))"
fi

# ---------------------------------------------------------------------------
# 3. Title update - also yours, also required
# ---------------------------------------------------------------------------
say "Locating title update"

if [ -z "$TITLE_UPDATE" ]; then
  # Reuse one already sitting next to the game data.
  TITLE_UPDATE=$(find "$ROOT" -maxdepth 1 -name 'TU_*' -print -quit 2>/dev/null)
fi
[ -n "$TITLE_UPDATE" ] && [ -f "$TITLE_UPDATE" ] \
  || die "Title update package not found. Pass --title-update PATH.
     The game's code is patched by it, so the build cannot link without it."
ok "title update: $(basename "$TITLE_UPDATE")"

# ---------------------------------------------------------------------------
# 4. MoltenVK - Vulkan on Metal, statically linked
# ---------------------------------------------------------------------------
say "Checking MoltenVK"

MVK_LIB="$MVK_DIR/MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"
if [ -f "$MVK_LIB" ]; then
  ok "MoltenVK static library present"
else
  say "Fetching MoltenVK $MVK_VERSION (this builds it; allow 10-20 minutes)"
  mkdir -p "$MVK_DIR"
  [ -d "$MVK_DIR/MoltenVK" ] \
    || git clone --depth 1 --branch "$MVK_VERSION" \
         https://github.com/KhronosGroup/MoltenVK.git "$MVK_DIR/MoltenVK" \
    || die "could not clone MoltenVK"
  ( cd "$MVK_DIR/MoltenVK" && ./fetchDependencies --ios && make ios ) \
    || die "MoltenVK failed to build"
  [ -f "$MVK_LIB" ] || die "MoltenVK built but $MVK_LIB is missing"
  ok "MoltenVK built"
fi

# ---------------------------------------------------------------------------
# 5. Signing identity
# ---------------------------------------------------------------------------
say "Checking code signing"

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
           | awk '/Apple Development|iPhone Developer/ {print $2; exit}')
[ -n "$IDENTITY" ] || die "No code signing identity in your keychain.
     Open Xcode > Settings > Accounts, sign in with your Apple ID, then
     Manage Certificates > + > Apple Development.
     A free Apple ID works; builds then expire after 7 days."

if [ -z "$TEAM_ID" ]; then
  # NOT from the certificate name: on a modern "Apple Development: Name (XXXX)"
  # certificate that parenthesised code is the developer's PERSON id, not the
  # team id, and signing with it produces an app the device refuses to install.
  # A provisioning profile carries the real team id.
  for pdir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
              "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    [ -d "$pdir" ] || continue
    for prof in "$pdir"/*.mobileprovision; do
      [ -e "$prof" ] || continue
      tmp=$(mktemp)
      if security cms -D -i "$prof" > "$tmp" 2>/dev/null; then
        # TeamIdentifier is an array; index it. Do not use a keypath through
        # Entitlements - those key names contain dots, which plutil reads as
        # further nesting.
        TEAM_ID=$(plutil -extract TeamIdentifier.0 raw -o - "$tmp" 2>/dev/null || true)
      fi
      rm -f "$tmp"
      [ -n "$TEAM_ID" ] && break 2
    done
  done
  [ -n "$TEAM_ID" ] || die "Could not determine your Team ID.
     Pass --team-id. You can find it at developer.apple.com > Membership,
     or in Xcode > Settings > Accounts (select your team)."
fi
if [ -z "$BUNDLE_ID" ]; then
  # An already-configured tree keeps the id it was built with: changing it
  # would orphan the app already on the phone (and its staged game data).
  if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    BUNDLE_ID=$(sed -n 's/^SKATE3_IOS_BUNDLE_ID:STRING=//p' "$BUILD_DIR/CMakeCache.txt" | head -1)
  fi
  # Otherwise derive it from the team, so two people's builds never collide.
  [ -n "$BUNDLE_ID" ] || BUNDLE_ID="com.$(echo "$TEAM_ID" | tr 'A-Z' 'a-z').skate3"
fi
ok "identity $IDENTITY, team $TEAM_ID, bundle $BUNDLE_ID"

# ---------------------------------------------------------------------------
# 6. Configure
# ---------------------------------------------------------------------------
say "Configuring the build"

if [ -f "$BUILD_DIR/CMakeCache.txt" ] \
   && grep -q "SKATE3_IOS_BUNDLE_ID:STRING=$BUNDLE_ID" "$BUILD_DIR/CMakeCache.txt" 2>/dev/null; then
  ok "already configured"
else
  # Ninja, never the Xcode generator: the Xcode generator collapses duplicate
  # source basenames into a single object file and the link then fails on
  # missing symbols. The SDK has several such collisions by design.
  cmake -S "$SRC" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DREXGLUE_USE_VULKAN=ON \
    -DREXGLUE_USE_D3D12=OFF \
    -DREXGLUE_IOS_MOLTENVK_STATIC_LIB="$MVK_LIB" \
    -DSKATE3_GAME_DATA_ROOT="$GAME_DIR" \
    -DSKATE3_TITLE_UPDATE_PACKAGE="$TITLE_UPDATE" \
    -DSKATE3_IOS_BUNDLE_ID="$BUNDLE_ID" \
    -DSKATE3_IOS_DEVELOPMENT_TEAM="$TEAM_ID" \
    || die "configure failed"
  ok "configured"
fi

# ---------------------------------------------------------------------------
# 7. Build - recompiles YOUR disc image on YOUR machine
# ---------------------------------------------------------------------------
say "Building (first run recompiles the game; expect 30-90 minutes)"

SAFE_BUILD=$(helper safe_build.sh)
if [ -n "$SAFE_BUILD" ]; then
  # Memory-guarded wrapper: pauses rather than lets the machine thrash.
  "$SAFE_BUILD" "$BUILD_DIR" skate3 "$JOBS" || die "build failed"
else
  cmake --build "$BUILD_DIR" --target skate3 -- -j "$JOBS" || die "build failed"
fi

APP="$BUILD_DIR/skate3.app"
[ -d "$APP" ] || die "build reported success but $APP is missing"
ok "built $APP ($(du -sh "$APP" | cut -f1))"

# ---------------------------------------------------------------------------
# 8. Sign and install
# ---------------------------------------------------------------------------
if [ "$SKIP_INSTALL" -eq 1 ]; then
  say "Done (--no-install)"
  echo "  App bundle: $APP"
  exit 0
fi

say "Signing and installing"
DEPLOY=$(helper deploy_ios.sh)
[ -n "$DEPLOY" ] || die "deploy_ios.sh not found next to $0 or in $ROOT"
if ! TEAM_ID="$TEAM_ID" "$DEPLOY" "$APP"; then
  # The build is the expensive part and it succeeded; a phone that is locked,
  # unplugged or untrusted is a retry, not a reason to throw that away.
  warn "The app built and signed, but installing to the phone did not succeed."
  cat <<RETRY

  Usually that means the phone is locked, unplugged, or has not trusted this
  Mac. Connect and unlock it, tap Trust if asked, then re-run:

      $DEPLOY

  That step alone takes seconds - it does not rebuild.

RETRY
  exit 1
fi

cat <<DONE

  Done.

  The app is on your phone. Game data is loaded at runtime, so stage it once:

    Finder > your iPhone > Files > Skate 3   <- drop the 'game' folder in

  Tuning presets live in $ROOT/ios_args/ and are copied to the app's
  Documents/user/ios_args.txt; no rebuild is needed to change them.

DONE
