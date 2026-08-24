# ios_args presets

Copy one onto the phone and relaunch; no rebuild needed:

    DEV=4680F865-DCF6-57D5-A4FC-1DDD0611277E
    xcrun devicectl device copy to --device $DEV \
      --domain-type appDataContainer --domain-identifier <your.bundle.id> \
      --user mobile --source ios_args/<file> \
      --destination Documents/user/ios_args.txt
    xcrun devicectl device process launch --device $DEV \
      --terminate-existing <your.bundle.id>

Note `--user mobile`, not `--username`, and the destination must be a file
path, not a directory.

## The setting that mattered most

    vulkan_mvk_synchronous_queue_submits=false

True keeps MoltenVK's encode - and its blocking wait for a CAMetalDrawable - on
whichever thread called vkQueueSubmit, which is the main thread. The hang
watchdog caught it parked in `getCAMetalDrawable()` with the command processor
idle on an empty ring. That wait expiring is what MoltenVK reports as
`VK_ERROR_DEVICE_LOST`, and `GraphicsSystem::OnHostGpuLossFromAnyThread` turns
that into `rex::FatalError` and an abort. A drawable timeout is not a lost
device. False moves the encode and the wait onto MoltenVK's own queue thread.

This alone is the difference between crashing after a minute and not crashing.

## Files

- `cap60_stores_tight.txt` — **current best.** 48.2 fps peak, ~40-45 sustained,
  p50 17.4ms, p95 39ms, footprint flat ~1.0-1.1GB.
- `known_good_30fps.txt` — cap 30. Locked 30 with p50 33.3 / p95 36.1 / max
  44.9ms in a good window, but it still collapsed after ~2 minutes of play.
  Kept for comparison, not recommended.
- `cap60_small_xenos_cache.txt` — **FAILED, do not use.** Cuts the Xenos
  texture cache to 128/256MB. Slow to load and hangs in the menu: that cache is
  not just the 2D/UI path even with the native scene renderer drawing the
  world. Kept so the experiment is not repeated.

## Measured, at the 60 cap

    fps=45.7  p50=17.9ms  p95=39.8ms  max=207.8ms
    fps=48.2  p50=17.4ms  p95=38.9ms  max=102.4ms
    fps=39.8  p50=17.9ms  p95=40.6ms  max=833.5ms

The median hardly moves while fps swings 40-48, because of vsync quantisation:
the median frame sits just past the 16.67ms line and anything that misses waits
a whole extra refresh. **Reaching a locked 60 needs roughly 1.5ms off the
median frame, not a 2x speedup.**

## What is still unfixed

Frames hitch on `table_miss` — a single descriptor-set allocation costing 3 to
13ms. The per-miss cost swings 40x between frames, which is memory stalls
rather than an algorithm, and it tracks the kernel's compressed footprint
exactly: 1546MB/306MB compressed at the collapse, 1019MB/86MB when clean.
Jetsam headroom was never the constraint — 800MB+ was free even at the worst.

The largest untaken memory lever: DXT1 is expanded to RGBA8 on upload, 32bpp
for a 4bpp source. The A15 has no BC hardware (now checked at runtime; MoltenVK
ships its own DXTn decompress compute shader for this case), so the fix is not
native BC but decoding DXT1 to **RGB565** — a straight 2x on the biggest
texture class, near-free in quality since a DXT1 block's endpoints are already
RGB565. Blocks in the 3-colour punch-out mode carry 1-bit alpha and must stay
RGBA8.

Full write-up, including profiling gotchas, is in the `skate3-ios-perf` memory.
