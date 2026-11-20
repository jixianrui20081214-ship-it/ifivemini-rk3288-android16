#!/bin/bash
# Build the iFive settings app into vendor-changes/priv-app/IfiveSettings/.
# Needs a JDK and the Android SDK (build-tools 36.1.0, platforms/android-36).
# A preinstalled priv-app does not need the platform key; the SDK debug key is used.
# targetSdk 34: android.preference does not handle the edge-to-edge layout forced
# from 35 on (the action bar covered the first switch).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SDK=${ANDROID_SDK:-$HOME/Android/Sdk}
BT=$SDK/build-tools/36.1.0
JAR=$SDK/platforms/android-36/android.jar
OUT=$HERE/../../vendor-changes/priv-app/IfiveSettings
W=$(mktemp -d "${TMPDIR:-/tmp}/ifive-settings.XXXXXX"); trap 'rm -rf "$W"' EXIT

"$BT/aapt2" compile --dir "$HERE/res" -o "$W/res.zip"
"$BT/aapt2" link -o "$W/u.apk" --manifest "$HERE/AndroidManifest.xml" -I "$JAR" "$W/res.zip" \
    --java "$W/gen" --min-sdk-version 30 --target-sdk-version 34 --version-code 1 --version-name 1.0
javac -source 11 -target 11 -Xlint:-options -cp "$JAR" -d "$W/cls" \
    $(find "$HERE/src" "$W/gen" -name '*.java')
"$BT/d8" --min-api 30 --lib "$JAR" --output "$W" $(find "$W/cls" -name '*.class')
( cd "$W" && zip -q u.apk classes.dex )
"$BT/zipalign" -f -p 4 "$W/u.apk" "$W/a.apk"
mkdir -p "$OUT"
"$BT/apksigner" sign --ks "$HOME/.android/debug.keystore" --ks-pass pass:android \
    --key-pass pass:android --ks-key-alias androiddebugkey --out "$OUT/IfiveSettings.apk" "$W/a.apk"
rm -f "$OUT/IfiveSettings.apk.idsig"
echo "built: vendor-changes/priv-app/IfiveSettings/IfiveSettings.apk"
