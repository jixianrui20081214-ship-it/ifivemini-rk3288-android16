#!/bin/bash
# Build the inputs of release-build/make-release.sh:
#   super.img      LineageOS 23.2 GSI system + the Tinker Board vendor with vendor-changes/ + odm
#   ramdisk.img, metadata.img, userdata-head-zero.img, rkdeveloptool   taken from a release zip
#
# Usage: ./build-android-images.sh <gsi> <release.zip> [output_dir]   (default: ./inputs)
#   <gsi>          the GSI system image: .img (raw or sparse), .img.xz or .tar.xz
#   <release.zip>  a release package from GitHub; its super.img provides vendor and odm

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
USAGE="usage: $0 <gsi.img|gsi.img.xz|gsi.tar.xz> <release.zip> [output_dir]"
GSI_SRC=${1:?$USAGE}
ZIP=${2:?$USAGE}
OUT_DIR=${3:-$HERE/inputs}
WORK_DIR="$HERE/out/super-work"

mkdir -p "$OUT_DIR" "$WORK_DIR"

echo "=== 1. Checking required tools ==="
MISSING=()
for tool in tar unxz unzip simg2img lpmake lpunpack debugfs e2fsck dd; do
    command -v "$tool" >/dev/null 2>&1 || MISSING+=("$tool")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "STOP: missing tools: ${MISSING[*]}"
    echo "Fedora (verified on fc45):  sudo dnf install -y android-tools e2fsprogs xz unzip"
    echo "Debian/Ubuntu:              sudo apt-get install -y e2fsprogs xz-utils unzip android-sdk-libsparse-utils"
    echo "                            lpmake/lpunpack are NOT covered by the Debian packages above;"
    echo "                            build them from AOSP system/extras/partition_tools."
    exit 1
fi

echo "=== 2. System image: $(basename "$GSI_SRC") ==="
GSI_IMG="$WORK_DIR/system.img"
[ -f "$GSI_SRC" ] || { echo "STOP: no such file: $GSI_SRC"; exit 1; }
RAW="$WORK_DIR/system.src.img"
case "$GSI_SRC" in
    *.tar.xz) tar -xJOf "$GSI_SRC" --wildcards '*.img' > "$RAW" ;;
    *.xz)     unxz -c "$GSI_SRC" > "$RAW" ;;
    *)        cp "$GSI_SRC" "$RAW" ;;
esac
# simg2img fails on a raw image; then the copy already is the raw image.
simg2img "$RAW" "$GSI_IMG" 2>/dev/null || mv "$RAW" "$GSI_IMG"
rm -f "$RAW"

echo "=== 3. From $(basename "$ZIP"): vendor, odm and the other images ==="
[ -f "$ZIP" ] || { echo "STOP: no such file: $ZIP"; exit 1; }
PKG="$WORK_DIR/package"
rm -rf "$PKG"; mkdir -p "$PKG"
unzip -q -j -o "$ZIP" '*/images/super.img' '*/images/ramdisk.img' '*/images/metadata.img' \
    '*/images/userdata-head-zero.img' '*/tools/rkdeveloptool' -d "$PKG"
lpunpack -p vendor -p odm "$PKG/super.img" "$WORK_DIR"
cp "$PKG/ramdisk.img" "$PKG/metadata.img" "$PKG/userdata-head-zero.img" "$PKG/rkdeveloptool" "$OUT_DIR/"
chmod +x "$OUT_DIR/rkdeveloptool"
rm "$PKG/super.img"

echo "=== 4. Patch vendor (HWC, power HAL, chgpolicy, init.rk3288.rc, VINTF manifest, build.prop) ==="
"$HERE/scripts/patch-vendor.sh" "$WORK_DIR/vendor.img" "$WORK_DIR/vendor-patched.img"

echo "=== 5. Device identity (brand/model/fingerprint) ==="
"$HERE/scripts/patch-identity.sh" "$GSI_IMG" "$WORK_DIR/vendor-patched.img" "$WORK_DIR/identity"

echo "=== 6. Pack super.img ==="
"$HERE/scripts/build-super.sh" "$WORK_DIR/identity/system.img" "$WORK_DIR/identity/vendor.img" "$WORK_DIR/odm.img" "$OUT_DIR/super.img"

echo
ls -lh "$OUT_DIR"
echo "Next: ./release-build/make-release.sh $OUT_DIR <date>"
