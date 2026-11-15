#!/bin/bash
# Build AOSP's non-secure Gatekeeper (hardware/interfaces/gatekeeper/aidl/software)
# as an armeabi-v7a vendor binary for the iFive mini 4S, with the Android NDK.
#
#   gatekeeper/build.sh <aosp-tree> <sysroot-libs>
#
# <aosp-tree>     LineageOS 23.2 / AOSP 16 source tree (read only; sources are
#                 compiled straight from it).
# <sysroot-libs>  directory with the tablet's /system/lib/liblog.so and
#                 /system/lib/libbinder_ndk.so (the LLNDK libraries the binary
#                 links to; `adb pull` them).
#
# The tablet has no TEE, so the Rockchip OP-TEE gatekeeper cannot work. This
# gatekeeper also serves ISharedSecret, so keystore2 negotiates one auth-token
# key between it and the software keymaster. Everything except liblog and
# libbinder_ndk is linked statically, so it runs on the API 30 vendor partition.
#
# Output: vendor-changes/bin/hw/android.hardware.gatekeeper-service.ifive
# Env: NDK (default ~/Android/Sdk/ndk/25.0.8775105), AIDL (default: newest SDK
#      build-tools aidl), JOBS.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(cd "${1:?usage: $0 <aosp-tree> <sysroot-libs>}" && pwd)
LIBS=$(cd "${2:?usage: $0 <aosp-tree> <sysroot-libs>}" && pwd)
NDK=${NDK:-$HOME/Android/Sdk/ndk/25.0.8775105}
AIDL=${AIDL:-$(ls -d "$HOME"/Android/Sdk/build-tools/*/aidl | sort -V | tail -1)}
OUT=$HERE/../out/gatekeeper
NAME=android.hardware.gatekeeper-service.ifive
API=30
for f in "$LIBS/liblog.so" "$LIBS/libbinder_ndk.so" "$NDK/build/cmake/android.toolchain.cmake" "$AIDL"; do
    [ -e "$f" ] || { echo "STOP: missing $f"; exit 1; }
done
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
CC="$TC/armv7a-linux-androideabi$API-clang"
CXX="$TC/armv7a-linux-androideabi$API-clang++"
mkdir -p "$OUT"

echo "== 1. BoringSSL libcrypto"
if [ ! -f "$OUT/ssl/libcrypto.a" ]; then
    cmake -S "$T/external/boringssl" -B "$OUT/ssl" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=armeabi-v7a -DANDROID_PLATFORM=android-$API \
        -DCMAKE_C_FLAGS="-Os -ffunction-sections -fdata-sections" \
        -DCMAKE_CXX_FLAGS="-Os -ffunction-sections -fdata-sections" >/dev/null
    ninja -C "$OUT/ssl" crypto >/dev/null
fi

echo "== 2. AIDL NDK stubs (frozen V1 interfaces)"
HI=$T/hardware/interfaces
GEN=$OUT/gen
rm -rf "$GEN"; mkdir -p "$GEN"
gen() { # <api dir> <version>
    local dir=$1 ver=$2 hash
    hash=$(tail -1 "$dir/.hash")
    find "$dir" -name '*.aidl' | while read -r f; do
        "$AIDL" --lang=ndk --structured --stability=vintf --version="$ver" --hash="$hash" \
            -I "$HI/gatekeeper/aidl/aidl_api/android.hardware.gatekeeper/1" \
            -I "$HI/security/sharedsecret/aidl/aidl_api/android.hardware.security.sharedsecret/1" \
            -I "$HI/security/keymint/aidl/aidl_api/android.hardware.security.keymint/1" \
            -I "$HI/security/secureclock/aidl/aidl_api/android.hardware.security.secureclock/1" \
            -h "$GEN/include" -o "$GEN/src" "$f"
    done
}
gen "$HI/gatekeeper/aidl/aidl_api/android.hardware.gatekeeper/1" 1
gen "$HI/security/sharedsecret/aidl/aidl_api/android.hardware.security.sharedsecret/1" 1
# Only the two parcelables the gatekeeper interface uses from KeyMint/SecureClock.
for f in HardwareAuthToken HardwareAuthenticatorType; do
    d=$HI/security/keymint/aidl/aidl_api/android.hardware.security.keymint/1
    "$AIDL" --lang=ndk --structured --stability=vintf --version=1 --hash="$(tail -1 "$d/.hash")" \
        -I "$d" -I "$HI/security/secureclock/aidl/aidl_api/android.hardware.security.secureclock/1" \
        -h "$GEN/include" -o "$GEN/src" "$d/android/hardware/security/keymint/$f.aidl"
done
d=$HI/security/secureclock/aidl/aidl_api/android.hardware.security.secureclock/1
"$AIDL" --lang=ndk --structured --stability=vintf --version=1 --hash="$(tail -1 "$d/.hash")" \
    -I "$d" -h "$GEN/include" -o "$GEN/src" "$d/android/hardware/security/secureclock/Timestamp.aidl"

echo "== 3. compile"
GK=$HI/gatekeeper/aidl/software
KM=$T/system/keymaster
SRCS=(
    "$GK/GateKeeper.cpp" "$GK/SharedSecret.cpp" "$HERE/service.cpp"
    "$T/system/gatekeeper/gatekeeper.cpp" "$T/system/gatekeeper/gatekeeper_messages.cpp"
    "$KM/km_openssl/ckdf.cpp" "$KM/km_openssl/hmac.cpp" "$KM/km_openssl/openssl_err.cpp"
    "$KM/android_keymaster/android_keymaster_utils.cpp" "$KM/android_keymaster/logger.cpp"
    "$KM/android_keymaster/serializable.cpp"
    "$T/system/libbase/logging.cpp" "$T/system/libbase/threads.cpp"
    "$T/system/libbase/strings.cpp" "$T/system/libbase/stringprintf.cpp"
    "$T/system/libbase/file.cpp" "$T/system/libbase/posix_strerror_r.cpp"
    "$T/system/libbase/errors_unix.cpp"
)
mapfile -t -O "${#SRCS[@]}" SRCS < <(find "$GEN/src" -name '*.cpp' | sort)
INC=(
    -I "$GEN/include" -I "$GK" -I "$T/system/gatekeeper/include"
    -I "$KM/include" -I "$KM" -I "$T/hardware/libhardware/include"
    -I "$T/system/libbase/include" -I "$T/system/logging/liblog/include"
    -I "$T/system/core/libcutils/include" -I "$T/system/core/libsystem/include"
    -I "$T/frameworks/native/libs/binder/ndk/include_ndk"
    -I "$T/frameworks/native/libs/binder/ndk/include_platform"
    -I "$T/frameworks/native/libs/binder/ndk/include_cpp"
    -I "$T/external/boringssl/src/include" -I "$T/external/scrypt/lib/crypto"
)
# NDK r25 headers predate these API level names used by binder_manager.h
DEF=(-D__ANDROID_API_U__=34 -D__ANDROID_API_V__=35 -DANDROID -D__ANDROID_VENDOR__ -D__ANDROID_VNDK__ -fvisibility=hidden -Os -ffunction-sections -fdata-sections -Wno-unused-parameter)
OBJ=$OUT/obj; rm -rf "$OBJ"; mkdir -p "$OBJ"
printf '%s\n' "${SRCS[@]}" | xargs -P "${JOBS:-8}" -I{} sh -c \
    'o="$0/$(echo "$1" | md5sum | cut -c1-12).o"; "$2" -std=c++20 $3 -c "$1" -o "$o" || { echo "FAILED: $1"; exit 255; }' \
    "$OBJ" {} "$CXX" "${DEF[*]} ${INC[*]}"
"$CC" -Os -ffunction-sections -fdata-sections -DHAVE_CONFIG_H -DUSE_OPENSSL_PBKDF2 -I "$T/external/scrypt/lib/crypto" -I "$T/external/scrypt/lib/util" -I "$T/external/scrypt" -I "$T/external/boringssl/src/include" \
    -c "$T/external/scrypt/lib/crypto/crypto_scrypt-ref.c" -o "$OBJ/scrypt.o"

echo "== 4. link"
mkdir -p "$HERE/../vendor-changes/bin/hw"
"$CXX" -o "$OUT/$NAME" "$OBJ"/*.o "$OUT/ssl/libcrypto.a" -static-libstdc++ \
    -L "$LIBS" -llog -lbinder_ndk -Wl,--allow-shlib-undefined -Wl,--gc-sections
"$TC/llvm-strip" "$OUT/$NAME"
cp "$OUT/$NAME" "$HERE/../vendor-changes/bin/hw/$NAME"
echo "built: vendor-changes/bin/hw/$NAME"
