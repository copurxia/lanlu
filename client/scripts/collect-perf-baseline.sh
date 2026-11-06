#!/usr/bin/env bash
#
# Cold-start + scroll baseline collector. Requires a connected Android device
# with USB debugging enabled.
#
# Usage:
#   ./scripts/collect-perf-baseline.sh [path-to-release.apk]
#
# Results:
#   /tmp/lanlu-perf-start-<run>.txt  adb am start -W output (TotalTime/WaitTime)
#   /tmp/lanlu-gfx-<run>.txt         dumpsys gfxinfo (jank + frame percentiles)
#   /tmp/lanlu-logcat-<run>.txt      ReactNativeJS / [perf] logcat lines
#
# Finally open the app: Settings -> Diagnostics -> View logs -> Share, and
# attach that file too. The app perf ring buffer is not readable from a
# non-debuggable release via adb.
set -euo pipefail

ADB="${ADB:-adb}"
if ! command -v "$ADB" >/dev/null 2>&1; then
  ADB="${ANDROID_HOME:-/opt/android-sdk}/platform-tools/adb"
fi
APK="${1:-$(cd "$(dirname "$0")/.." && pwd)/../lanlu-client-1.0-release.apk}"
PKG="com.lanluclient"
ACTIVITY="$PKG/.MainActivity"

if ! "$ADB" get-state >/dev/null 2>&1; then
  echo "No adb device. Connect a device with USB debugging enabled." >&2
  exit 1
fi
if [ ! -f "$APK" ]; then
  echo "APK not found: $APK" >&2
  exit 1
fi

"$ADB" install -r "$APK"

for run in 1 2 3; do
  echo "=== run $run ==="
  "$ADB" shell am force-stop "$PKG"
  sleep 1
  "$ADB" shell dumpsys gfxinfo "$PKG" reset >/dev/null 2>&1 || true
  "$ADB" logcat -c

  # Cold start: app process is gone, measured by the platform.
  "$ADB" shell am start -W -n "$ACTIVITY" | tee "/tmp/lanlu-perf-start-$run.txt"
  sleep 8

  # One vertical drag on the Home feed / rows.
  "$ADB" shell input swipe 540 1600 540 600 300
  sleep 1
  "$ADB" shell input swipe 540 600 540 1600 300
  sleep 2

  "$ADB" shell dumpsys gfxinfo "$PKG" > "/tmp/lanlu-gfx-$run.txt"
  "$ADB" logcat -d -v time | grep -aE "ReactNativeJS|\[perf\]" > "/tmp/lanlu-logcat-$run.txt" || true

  echo "start: $(grep -E 'TotalTime|WaitTime' "/tmp/lanlu-perf-start-$run.txt" | tr '\n' ' ')"
  echo "gfx:   $(grep -E 'Total frames rendered|Janky frames|90th percentile|95th percentile|99th percentile' "/tmp/lanlu-gfx-$run.txt" | tr '\n' ' ')"
done

echo
echo "Now open Settings -> Diagnostics -> View logs -> Share and attach the log."
echo "The [perf] lines contain s=<session> for each cold-start process."
