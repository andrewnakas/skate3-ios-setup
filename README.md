# skate3-ios-setup

Build the Skate 3 recompilation for iOS **from your own disc image**, on your
own Mac, signed with your own Apple ID, installed on your own iPhone.

```
./skate3-setup.sh --iso ~/Downloads/skate3.iso \
                  --title-update ~/Downloads/TU_12K2276_000000C000000.00000000000O3
```

That is the whole thing. It checks your tools, extracts your disc image,
recompiles it, builds the app, signs it, and installs it.

## What this ships, and what it does not

**This repository contains no game code and no game content.** It is a build
script. Everything derived from the game is produced on your machine, from the
disc image you supply, and never leaves it.

You need a legally obtained copy of Skate 3 and the ability to dump it. Nothing
here will find, download, or provide one.

## Requirements

| | |
|---|---|
| **macOS** | The iOS toolchain and code signing only exist here. |
| **Xcode** | Full Xcode, not just Command Line Tools — the iOS SDK ships only with Xcode. ~15GB. |
| **Homebrew packages** | `brew install cmake ninja` |
| **Apple ID** | Free works — verified, not assumed. See the note below. |
| **Disk** | ~12GB free: ~6GB extracted game data, ~300MB generated sources, ~2GB build. |
| **RAM** | 8GB is enough. The script picks a job count from your RAM; the generated translation units are large and over-parallelising will thrash a small machine. |
| **Your Skate 3 disc image** | Plus its title update package. |
| **Time** | 30–90 minutes on the first run, depending on the machine. Later runs are incremental. |

## The title update is not optional

The game's code is patched by the title update, and its functions are linked
into the binary. Without it the build fails at link time on an undefined
symbol. Pass it with `--title-update`.

## About signing and the 7-day thing

The app is signed with **your** Apple ID, because the binary is yours — it was
built on your machine from your disc.

- **Free Apple ID**: works, but iOS expires the signature after **7 days** and
  the app stops launching. Re-run `./deploy_ios.sh` to re-sign, or use
  [SideStore](https://sidestore.io) / AltStore to refresh it automatically.
- **Paid account** ($99/yr): the same, but yearly.

**You do not need a paid account for the memory entitlements.** The build
requests `extended-virtual-addressing` and `increased-memory-limit`, neither of
which a free personal team can be granted — but a build signed *without* them
installs, launches and plays. That was verified on device by re-signing the
same binary with both keys stripped: it ran at a 463MB footprint against
1634MB of headroom. Expanding opaque DXT1 to RGB565 brought the resident set
under the default jetsam ceiling, so the increased limit stopped mattering, and
extended virtual addressing turns out not to be needed on an A15.

If Xcode will not mint a profile for your team, delete both keys from
`cmake/ios/skate3.entitlements` rather than buying an account.

## Staging game data

Game assets are loaded at runtime, not baked into the app. After the first
install, put them on the phone once:

**Finder → your iPhone → Files → Skate 3** — drop the `game` folder in.

## Performance tuning, no rebuild required

Launch options live in `Documents/user/ios_args.txt` inside the app's container
and are read at startup, so tuning needs no rebuild. Presets are in
`../ios_args/`:

- `cap60_best.txt` — current best. On an iPhone 13 mini this runs roughly
  49–51 fps with a 16.9ms median frame, and has touched 58.9 fps with a 17.2ms
  95th percentile in a clean window.
- `cap60_phase12_off.txt` — the same build with the descriptor-set recycling
  and RGB565 texture path disabled, for A/B comparison.
- `known_good_30fps.txt` — a conservative 30fps cap.

Copy one across with:

```
xcrun devicectl device copy to --device <UDID> \
  --domain-type appDataContainer --domain-identifier <your.bundle.id> \
  --user mobile --source ../ios_args/cap60_best.txt \
  --destination Documents/user/ios_args.txt
```

Note `--user mobile` (not `--username`), and the destination must be a file
path rather than a directory.

## Options

```
--iso PATH             Your disc image (required on the first run)
--title-update PATH    Title update package (required on the first run)
--team-id ID           Apple Developer Team ID. Auto-detected from your
                       provisioning profiles when possible.
--bundle-id ID         Defaults to the id an existing build used, else one
                       derived from your team id.
--jobs N               Parallel compile jobs. Defaults from your RAM.
--no-install           Build and sign only; leave the device alone.
```

Re-running is safe and resumable. Each step detects work already done, so a
failure part-way through does not restart the expensive parts.

## If something goes wrong

**"Xcode is required"** — you have only the Command Line Tools. Install Xcode,
then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

**"No code signing identity"** — Xcode → Settings → Accounts, sign in, then
Manage Certificates → **+** → Apple Development.

**"Could not determine your Team ID"** — pass `--team-id`. It is on
developer.apple.com under Membership, or in Xcode → Settings → Accounts.

**Install fails, build succeeded** — the phone is locked, unplugged, or has not
trusted this Mac. Fix that and run `../deploy_ios.sh`; it takes seconds and
does not rebuild.

**The build wedges the machine** — lower `--jobs`. The default is derived from
RAM but an unusually fat translation unit can still spike.

**The app launches to a black screen** — game data is not staged yet. See
"Staging game data" above.

## Why there is no downloadable IPA

Because the recompiled binary contains the game's code. A prebuilt IPA would be
redistribution of it, which is exactly what building locally avoids. The
Ship of Harkinian and Zelda 64: Recompiled projects ship binaries with no game
content for the same reason — their engine exists separately from the game.
A static recompilation has no such separation: the recompiled functions *are*
the game, so the build has to happen on your machine, from your copy.
