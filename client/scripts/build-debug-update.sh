#!/usr/bin/env bash
# Build a new debug APK, bump its versionCode, and publish it to the LAN update
# service. The installed debug app checks /version.json on every resume.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
JAVA_HOME="${JAVA_HOME:-/opt/jdk21}"
PUBLISH_DIR="${LANLU_UPDATE_DIR:-/tmp/lanlu-update}"
VERSION_FILE="$ROOT/android/version-code.txt"
APK_OUT="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
AAPT="$(find "$ANDROID_HOME/build-tools" -name aapt -type f | sort -V | tail -1)"

mkdir -p "$PUBLISH_DIR"
current="$(cat "$VERSION_FILE" 2>/dev/null || echo 1)"
next=$((current + 1))
echo "$next" > "$VERSION_FILE"

cd "$ROOT/android"
JAVA_HOME="$JAVA_HOME" PATH="$JAVA_HOME/bin:$PATH" \
ANDROID_HOME="$ANDROID_HOME" ANDROID_SDK_ROOT="$ANDROID_HOME" \
GRADLE_OPTS="-Djava.net.preferIPv4Stack=true" \
./gradlew assembleDebug --no-daemon --console=plain --max-workers=2 \
  --project-cache-dir=/tmp/lanlu-gradle-cache-debug \
  -Dorg.gradle.java.installations.paths=/opt/jdk17 \
  -Dorg.gradle.java.installations.auto-download=false \
  -Dkotlin.daemon.jvmargs=-Xmx1536m

cp "$APK_OUT" "$PUBLISH_DIR/app-debug.apk"
sha="$(sha256sum "$PUBLISH_DIR/app-debug.apk" | awk '{print $1}')"
pkg_line="$($AAPT dump badging "$PUBLISH_DIR/app-debug.apk" | sed -n '1p')"
code="$(printf '%s' "$pkg_line" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")"
name="$(printf '%s' "$pkg_line" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")"
cat > "$PUBLISH_DIR/version.json" <<JSON
{"versionCode":${code:-0},"versionName":"${name:-unknown}","sha256":"$sha","url":"http://192.168.0.111:8083/app-debug.apk"}
JSON
cat "$PUBLISH_DIR/version.json"

if [ -f /tmp/lanlu-update-server.pid ] && kill -0 "$(cat /tmp/lanlu-update-server.pid)" 2>/dev/null; then
  echo "update server already running with pid $(cat /tmp/lanlu-update-server.pid)"
else
  nohup python3 -m http.server 8083 --bind 0.0.0.0 --directory "$PUBLISH_DIR" \
    > /tmp/lanlu-update-server.log 2>&1 &
  echo $! > /tmp/lanlu-update-server.pid
  echo "update server started with pid $(cat /tmp/lanlu-update-server.pid)"
fi
