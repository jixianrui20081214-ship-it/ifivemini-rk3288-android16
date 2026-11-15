#!/bin/bash
# Build the software Keymaster 4.0 service for the iFive mini 4S vendor partition
# (armeabi-v7a, API 30) with the Android NDK compiler.
#
#   keymaster/build.sh <aosp-tree> <vendor-libs>
#
# <aosp-tree>    LineageOS 23.2 / AOSP 16 source tree with its out/ (read only).
#                Used for libc++/libhidl headers and the generated
#                android.hardware.keymaster@4.0 headers.
# <vendor-libs>  the tablet's VNDK v30 libraries the service links to:
#                /apex/com.android.vndk.v30/lib/{android.hardware.keymaster@4.0,
#                libhidlbase,libutils,libcutils,libbase,libcrypto,libc++}.so, plus
#                /vendor/lib/libkeymaster4support.so and /system/lib/liblog.so.
#
# The Keymaster sources are android-11.0.0_r48 system/keymaster (the release the
# vendor partition was built against), with the libhardware and BoringSSL headers
# of the same release (this keymaster uses the keymaster0/1/2 HAL headers and
# OpenSSL structs that newer releases dropped or hid); all are downloaded into
# out/keymaster/. keymaster/patches/ are applied to the Keymaster sources.
# The service is linked against the device libc++ (not the NDK one), because it
# passes std:: types to libhidlbase.
#
# Output: vendor-changes/bin/hw/android.hardware.keymaster@4.0-service.ifive
# Env: NDK (default ~/Android/Sdk/ndk/25.0.8775105), JOBS.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(cd "${1:?usage: $0 <aosp-tree> <vendor-libs>}" && pwd)
LIBS=$(cd "${2:?usage: $0 <aosp-tree> <vendor-libs>}" && pwd)
NDK=${NDK:-$HOME/Android/Sdk/ndk/25.0.8775105}
OUT=$HERE/../out/keymaster
NAME=android.hardware.keymaster@4.0-service.ifive
TAG=android-11.0.0_r48
API=30
GEN=$T/out/soong/.intermediates
for f in android.hardware.keymaster@4.0.so libhidlbase.so libutils.so libcutils.so libbase.so libcrypto.so \
         libc++.so libkeymaster4support.so liblog.so; do
    [ -f "$LIBS/$f" ] || { echo "STOP: missing $LIBS/$f"; exit 1; }
done
[ -d "$GEN/hardware/interfaces/keymaster/4.0/android.hardware.keymaster@4.0_genc++_headers" ] ||
    { echo "STOP: $T/out has no generated keymaster@4.0 headers"; exit 1; }
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
CC="$TC/armv7a-linux-androideabi$API-clang"
CXX="$TC/armv7a-linux-androideabi$API-clang++"
mkdir -p "$OUT"

echo "== 1. Keymaster sources ($TAG)"
KM=$OUT/src
if [ ! -f "$KM/Android.bp" ]; then
    mkdir -p "$KM"
    curl -sfL "https://android.googlesource.com/platform/system/keymaster/+archive/refs/tags/$TAG.tar.gz" |
        tar xz -C "$KM"
fi
for p in "$HERE"/patches/*.patch; do
    patch -d "$KM" -p1 -N -s --dry-run < "$p" >/dev/null 2>&1 && patch -d "$KM" -p1 -N -s < "$p"
done

# libhardware headers of the same release (keymaster0/1/2 HAL headers, gone in 16)
HW=$OUT/libhardware-include
if [ ! -f "$HW/hardware/keymaster0.h" ]; then
    mkdir -p "$HW"
    curl -sfL "https://android.googlesource.com/platform/hardware/libhardware/+archive/refs/tags/$TAG/include.tar.gz" |
        tar xz -C "$HW"
fi

echo "== 2. BoringSSL headers ($TAG)"
# Headers only: the service links the device libcrypto.so (VNDK v30), which is
# this same BoringSSL release.
BS=$OUT/boringssl-include
if [ ! -f "$BS/openssl/evp.h" ]; then
    mkdir -p "$BS"
    curl -sfL "https://android.googlesource.com/platform/external/boringssl/+archive/refs/tags/$TAG/src/include.tar.gz" |
        tar xz -C "$BS"
fi

echo "== 3. compile"
# libkeymaster_portable, libkeymaster_messages, libsoft_attestation_cert,
# libpuresoftkeymasterdevice and libkeymaster4 from the $TAG Android.bp
mapfile -t SRCS < <(cd "$KM" && sed -n '/name: "libkeymaster_portable"/,/^}/p' Android.bp |
    grep -oE '"[a-z_/0-9]+\.(cpp|c)"' | tr -d '"' | sed "s|^|$KM/|")
SRCS+=(
    "$KM/contexts/soft_attestation_cert.cpp"
    "$KM/android_keymaster/keymaster_configuration.cpp"
    "$KM/contexts/pure_soft_keymaster_context.cpp"
    "$KM/contexts/soft_keymaster_logger.cpp"
    "$KM/km_openssl/soft_keymaster_enforcement.cpp"
    "$KM/legacy_support/keymaster_passthrough_key.cpp"
    "$KM/legacy_support/keymaster_passthrough_engine.cpp"
    "$KM/legacy_support/keymaster_passthrough_operation.cpp"
    "$KM/ng/AndroidKeymaster4Device.cpp"
    "$HERE/service.cpp"
)
# keymaster_stl.cpp provides the STL subset for trusty; here the real libc++ is used
SRCS=("${SRCS[@]/$KM\/android_keymaster\/keymaster_stl.cpp}")
INC=(
    -nostdinc++ -isystem "$T/external/libcxx/include" -isystem "$T/external/libcxxabi/include"
    -I "$KM/include" -I "$KM/ng/include" -I "$KM" -I "$HW"
    -I "$T/hardware/interfaces/keymaster/4.0/support/include"
    -I "$GEN/hardware/interfaces/keymaster/4.0/android.hardware.keymaster@4.0_genc++_headers/gen"
    -I "$GEN/system/libhidl/transport/base/1.0/android.hidl.base@1.0_genc++_headers/gen"
    -I "$GEN/system/libhidl/transport/manager/1.0/android.hidl.manager@1.0_genc++_headers/gen"
    -I "$T/system/libhidl/base/include" -I "$T/system/libhidl/transport/include"
    -I "$T/system/libfmq/include" -I "$T/system/libfmq/base" -I "$T/system/libhwbinder/include"
    -I "$T/system/libbase/include" -I "$T/system/logging/liblog/include"
    -I "$T/system/core/libcutils/include" -I "$T/system/core/libutils/include"
    -I "$T/system/core/libsystem/include" -I "$T/system/core/libvndksupport/include"
    -I "$BS"
)
DEF=(-fno-rtti -DANDROID -D__ANDROID_VENDOR__ -D__ANDROID_VNDK__ -DKEYMASTER_NAME_TAGS -DBORINGSSL_NO_CXX
     -Os -ffunction-sections -fdata-sections -Wno-unused-parameter -Wno-deprecated-declarations
     -Wno-c99-designator)
OBJ=$OUT/obj; rm -rf "$OBJ"; mkdir -p "$OBJ"
for s in "${SRCS[@]}"; do [ -n "$s" ] && echo "$s"; done | xargs -P "${JOBS:-8}" -I{} sh -c '
    o="$0/$(echo "$1" | md5sum | cut -c1-12).o"
    case "$1" in *.c) "$2" $4 -c "$1" -o "$o" ;; *) "$3" -std=c++17 $4 -c "$1" -o "$o" ;; esac ||
        { echo "FAILED: $1"; exit 255; }' "$OBJ" {} "$CC" "$CXX" "${DEF[*]} ${INC[*]}"

echo "== 4. link"
mkdir -p "$HERE/../vendor-changes/bin/hw"
"$CXX" -nostdlib++ -o "$OUT/$NAME" "$OBJ"/*.o -Wl,--gc-sections \
    -L "$LIBS" -lhidlbase -lkeymaster4support "$LIBS/android.hardware.keymaster@4.0.so" \
    -lutils -lcutils -lbase -lcrypto -llog -lc++
"$TC/llvm-strip" "$OUT/$NAME"
cp "$OUT/$NAME" "$HERE/../vendor-changes/bin/hw/$NAME"
echo "built: vendor-changes/bin/hw/$NAME"
