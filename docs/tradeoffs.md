# Settings with a cost

Settings this project keeps that trade something away. Measured on one tablet, janky frames from `hwc/test/release-check.sh` / `real3.sh`.

| Setting | Where | Gain | Cost |
|---|---|---|---|
| DDR fixed at 456 MHz while the screen is on (396 MHz with no display scanning out); no load-based scaling. iFive settings can keep 396 MHz | `init.rk3288.rc`, `rk3288_dmc` | shade animation jank 42% → 34%; no rate switch during scan-out (the vblank is 194 µs, shorter than a switch) | more power than 396 MHz while the screen is on and idle (not measured) |
| Three framebuffers (`ro.surface_flinger.max_frame_buffer_acquired_buffers=3`) | `vendor-changes/build.prop` | recents opened from an app 78-84% → 43-47% | one more 12 MiB buffer |
| SurfaceFlinger `debug.sf.*duration` 18 / 16.6 ms (Tinker Board values) | `vendor-changes/build.prop` | vs SurfaceFlinger defaults: recents 22.7/22.8% vs 23.4/25.6%, landscape drawer 17.6/16.3% vs 22.2/22.4%, landscape shade 50.7/53.3% vs 56.5/54.9% | touch-to-display latency up to one frame longer |
| `swappiness=100`, zram 50% of RAM | `init.rk3288.rc`, fstab | fewer background apps killed | CPU time for compression |
| Screen density 320 (stock Android 6 value; the panel is about 324 ppi) | `vendor-changes/build.prop` | UI at its designed physical size | landscape quick settings show 2 rows of tiles; below about 256 dpi they show 3. Users can set their own with `wm density` |
| Deep Doze without a motion sensor (`config_autoPowerModeUseMotionSensor=false`; iFive settings turns it off) | `overlays/deep-doze/` | deep Doze about 2.5 minutes after screen off and unplug: background jobs and alarms wait for maintenance windows 1, 2, 4, 6 h apart | moving the tablet with the screen off does not end deep Doze; it ends at screen on or plug in |
