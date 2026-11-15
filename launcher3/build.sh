#!/bin/bash
# build.sh <Launcher3QuickStep.apk> <out-dir>
# Builds <out-dir>/Launcher3QuickStep.apk from the APK that ships on the tablet: the stock app with
# the themed-icon raster cache, signed with the AOSP testkey (the key the stock APK is signed with),
# so `adb install -r` takes it as an update of the system app.
# Needs: java, the Android SDK (build-tools, platforms/android-36), baksmali/smali 2.5.2 jars,
# and the AOSP testkey (build/make/target/product/security/testkey.{pk8,x509.pem}).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
APK=${1:?usage: $0 <Launcher3QuickStep.apk> <out-dir>}; OUT=${2:?usage: $0 <apk> <out-dir>}
SDK=${ANDROID_SDK:-$HOME/Android/Sdk}; BT=$SDK/build-tools/${BUILD_TOOLS:-36.1.0}
ANDROID_JAR=$SDK/platforms/android-36/android.jar
SMALI_DIR=${SMALI_DIR:?set SMALI_DIR to the directory holding baksmali.jar and smali.jar}
KEY=${TESTKEY:?set TESTKEY to the testkey path without extension (…/security/testkey)}
WANT_CERT=a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd); W=$(mktemp -d "$OUT/.work.XXXXXX"); trap 'rm -rf "$W"' EXIT

# 0. the input must be the APK this patch was written against (stock testkey signature)
"$BT/apksigner" verify --print-certs "$APK" | grep -q "SHA-256 digest: $WANT_CERT" \
  || { echo "STOP: $APK is not signed with the expected testkey certificate"; exit 3; }

# 1. ThemedIconCache -> dex -> smali
mkdir -p "$W/cls" "$W/dex"
javac -source 8 -target 8 -nowarn -Xlint:-options -bootclasspath "$ANDROID_JAR" -d "$W/cls" \
  $(find "$HERE/src" "$HERE/stubs" -name '*.java')
"$BT/d8" --min-api 30 --lib "$ANDROID_JAR" --classpath "$W/cls" --output "$W/dex" \
  "$W/cls/com/android/launcher3/icons/mono/ThemedIconCache.class"
java -jar "$SMALI_DIR/baksmali.jar" d -a 30 "$W/dex/classes.dex" -o "$W/cache-smali"

# 2. the dex holding ThemedIconDelegate: disassemble, add the cache, patch, reassemble
unzip -q -o "$APK" 'classes*.dex' -d "$W/apk"
DEX=""
for d in "$W"/apk/classes*.dex; do
  java -jar "$SMALI_DIR/baksmali.jar" d -a 36 "$d" -o "$W/smali-$(basename "$d" .dex)"
  [ -f "$W/smali-$(basename "$d" .dex)/com/android/launcher3/icons/mono/ThemedIconDelegate.smali" ] && DEX=$(basename "$d")
done
[ -n "$DEX" ] || { echo "STOP: ThemedIconDelegate not found in $APK"; exit 3; }
S=$W/smali-${DEX%.dex}
cp "$W/cache-smali/com/android/launcher3/icons/mono/ThemedIconCache.smali" "$S/com/android/launcher3/icons/mono/"
python3 "$HERE/patch-delegate.py" "$S/com/android/launcher3/icons/mono/ThemedIconDelegate.smali"
java -jar "$SMALI_DIR/smali.jar" a -a 36 "$S" -o "$W/$DEX"

# 3. replace that dex in a copy of the APK (stored, like the original), align, sign
cp "$APK" "$W/unsigned.apk"
( cd "$W" && zip -q -0 -X unsigned.apk "$DEX" )
"$BT/zipalign" -f -p 4 "$W/unsigned.apk" "$W/aligned.apk"
"$BT/apksigner" sign --key "$KEY.pk8" --cert "$KEY.x509.pem" --out "$OUT/Launcher3QuickStep.apk" "$W/aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT/Launcher3QuickStep.apk" | grep -q "SHA-256 digest: $WANT_CERT"

sha256sum "$OUT/Launcher3QuickStep.apk"
