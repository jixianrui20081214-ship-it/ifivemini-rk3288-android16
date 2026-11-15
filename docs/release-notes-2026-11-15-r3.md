# iFive mini 4S - Android 16 GSI release 2026-11-15-r3 (LineageOS 23.2)

Changes since 2026-11-15-r2. Measured on one tablet (ML5RRJ6M5C), `/data` kept.

## Battery and power
- DDR drops to 396 MHz while no display is scanning out and goes back to 456 MHz when the screen turns on (kernel `dmc-sync` notifier, `rk3288_dmc`). Checked twice: off 396 MHz, on 456 MHz, no crash.
- Charger input limit moved from the `chgpolicy.sh` loop (woke every 30 s) into the `rn5t618` driver (`chg_boost`, set by init from `persist.vendor.chg.boost`). The limit goes from 500 mA to 2 A at 64 s after boot.
- No `ro.hdmi.device_type`: the `HdmiCecLocalDevicePlayback` wakelock is gone.
- PMIC wakeup sources are labelled `sysfs_wakeup`, so `system_suspend` can read them.
- Removed `printk.devkmsg=on` from the kernel command line.

## Security
- SELinux enforcing. `adb root` works under enforcing (AOSP userdebug `permissive su` added to the GSI policy).
- adb asks for authorisation (`ro.adb.secure=1`).

## Display
- HWC primary connector is DSI (the Tinker Board value was HDMI-A).
- Grayscale, night light and extra dim stay on when the screen is still.
- Lowest backlight level is duty 61.

## Cleanup of Tinker Board vendor leftovers
- Removed properties the vendor init may not set, or that nothing reads: `ro.product.*` (the vendor keeps `ro.product.vendor.*`), `ro.adb.secure`, `ro.boot.vr`, `ro.boot.noril`, `ro.ril.ecclist`, `rild.*`, `ril.function.dataonly`, `wifi.supplicant_scan_interval`, Bluetooth snoop/timeout properties, `persist.tegra.nvmmlite`, `ro.rk.homepage_base` (split over three broken lines), `ro.safemode.disabled`.
- `init.rk3288.rc`: removed KSM writes (`CONFIG_KSM` is not built), `/dev/video_state`, and a chmod on a devfreq node that does not exist.
- `init.connectivity.rc`: removed the NFC lines (no NFC controller).
- `vendor.rga_*` properties labelled so the HWC can set them.
- USB PHY and headset extcon cable nodes labelled `sysfs_extcon`, so `system_server` can read them.
- `init.connectivity.rc`: removed `ro.bt.bdaddr_path=/data/misc/bluetooth/bdaddr` (the file does not exist and vendor processes may not read that directory). The Bluetooth HAL now goes straight to `persist.service.bdroid.bdaddr`, the address it was already using.
- `/dev/block/zram0` labelled `swap_block_device` (AOSP label) instead of the Tinker `zram_device`, so `mkswap` can query the device size.
- init may write `queue/discard_max_bytes` on the eMMC (labelled `sysfs_mmc`). The eMMC hardware limit is 34078720 bytes, so the effective value does not change; discard was already on for `/data` and `/metadata`.
- Camera HAL and the OMX codec may set the `vendor.rga_*` version properties their librga writes, and read `/proc/version` (the Rockchip JPEG encoder and OMX check the kernel version).
- `media.settings.xml` labelled `vendor_system_public_prop` instead of `vendor_camera_prop`, so apps using CameraX can read it (it points `CamcorderProfile` at the media profiles file).
- `persist.vendor.camera.privapp.list` labelled `vendor_system_public_prop`: the LineageOS framework reads it in every app that opens a camera, and the Tinker `persist.vendor.camera.` prefix made it unreadable for apps.
- `/vendor/build.prop` mode 0644 (AOSP default) instead of 0600.
- Removed vendor policy rules that A16 neverallows and nothing here uses: `execmod` on `oemfs` for `untrusted_app*`, and `mounton` on `/proc/cpuinfo` for `shell`.

## Storage
- `/data` keeps ext4 quota and the project feature. TrebleDroid's fs_mgr (patch "Disable quotas on legacy devices with encryption disabled") removed them on every boot on a device without file encryption, so vold could not set project IDs and Recorder crashed creating `Android/data/org.lineageos.recorder`. `scripts/patch-fsmgr-quota.py` turns that check off in the four system binaries that carry a copy of fs_mgr (`libfs_mgr.so`, `libfs_mgr_binder.so`, `vold`, `update_engine`); quota then follows the fstab `quota` flag, as in AOSP. On an existing `/data` the features are added at boot by fs_mgr's tune2fs; it skips a filesystem whose journal is dirty, so after flashing they can appear one reboot later (checked on the tablet: after the second boot `/data` had `quota project`, and Recorder's `Android/data` folder got project ID 20192).

- The kernel command line sets `androidboot.fstab_suffix=rk30board.emmc`. vold looks for `fstab.<ro.boot.hardware>` = `fstab.rk30board`, which does not exist (the vendor fstab is `fstab.rk30board.emmc`), so it read no fstab: `vold.has_quota`, `vold.has_reserved` and `vold.has_adoptable` were 0 and no microSD slot was registered. First-stage init still finds the ramdisk `/fstab.rk30board` through the `hardware` fallback. Checked on the tablet: all three properties are 1, boot and SELinux enforcing unchanged.

## Lock screen and keystore
- Lock-screen PIN, pattern and password work. Before, setting one succeeded but it could never be verified again (`UserNotAuthenticatedException`), which locked the user out.
- The board has no TEE (no `/dev/tee*`), so the Rockchip OP-TEE services are removed: gatekeeper, weaver, `tee-supplicant`, their libraries and trusted apps.
- New `android.hardware.gatekeeper-service.ifive`: AOSP's software gatekeeper (`gatekeeper/build.sh`), which also serves `ISharedSecret/gatekeeper` so keystore2 negotiates one auth-token key with the keymaster.
- New `android.hardware.keymaster@4.0-service.ifive` (`keymaster/build.sh`): the same Android 11 software Keymaster as before, now built from a script in this repository, with the upstream fix for its auth-token size check (it compared against the size of a pointer and rejected every token).

## Other vendor changes
- Screen density 320 (`ro.sf.lcd_density`), as on the stock Android 6 firmware.
- Removed Tinker Board services whose programs are not on this vendor or system: `install-recovery.sh`, `rk_store_keybox`, `displayd`, `gpsd`, the `dhcpcd`/`iprenew` services, PPPoE helpers, `wfd`, `getbootmode`, `/sbin/watchdogd`, the Widevine data-move script, and the `mtd@system` mounts in the charger trigger.

## Checked on the tablet
- `scripts/magisk-install-data.sh` under enforcing (run after `adb root`): Magisk 31.0, `su -c id` gives `u:r:magisk:s0`.
- Wi-Fi connects and DNS resolves; cameras (2), accelerometer/compass/gyroscope, speaker and Bluetooth present.

## Known
- Landscape notification shade: about 52-56% janky frames.
- Landscape app drawer: about 65% janky frames with themed icons on a non-circle shape. The release's `ifive-mini4s-launcher3-icon-cache.apk` (source in `launcher3/`) caches the clipped icon and brings it to 12-17%.
- `CONFIG_DEBUG_LIST` must stay on: the vendor `bcmdhd.ko` needs it (turning it off disabled Wi-Fi in a test build).
