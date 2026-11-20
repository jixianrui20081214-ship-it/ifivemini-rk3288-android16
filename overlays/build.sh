#!/bin/bash
# Build the vendor RROs in this directory into vendor-changes/overlay/.
# Needs the Android SDK (build-tools 36.1.0, platforms/android-36).
# Overlays preinstalled on /vendor are not checked against the platform
# certificate, so the SDK debug key is enough.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SDK=${ANDROID_SDK:-$HOME/Android/Sdk}
BT=$SDK/build-tools/36.1.0
W=$(mktemp -d "${TMPDIR:-/tmp}/rro.XXXXXX"); trap 'rm -rf "$W"' EXIT

build() { # <source dir> <apk name>
    "$BT/aapt2" compile --dir "$HERE/$1/res" -o "$W/$2.res.zip"
    "$BT/aapt2" link -o "$W/$2.unsigned.apk" --manifest "$HERE/$1/AndroidManifest.xml" \
        -I "$SDK/platforms/android-36/android.jar" -R "$W/$2.res.zip" \
        --auto-add-overlay --min-sdk-version 36 --target-sdk-version 36
    "$BT/zipalign" -f -p 4 "$W/$2.unsigned.apk" "$W/$2.aligned.apk"
    "$BT/apksigner" sign --ks "$HOME/.android/debug.keystore" --ks-pass pass:android \
        --key-pass pass:android --ks-key-alias androiddebugkey \
        --out "$HERE/../vendor-changes/overlay/$2.apk" "$W/$2.aligned.apk"
    rm -f "$HERE/../vendor-changes/overlay/$2.apk.idsig"
    echo "built: vendor-changes/overlay/$2.apk"
}

build deep-doze DeepDoze
