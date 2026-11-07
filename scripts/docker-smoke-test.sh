#!/usr/bin/env bash
# Verify that the runtime image can actually start the bundled binary:
# every NEEDED library resolves, the external tools and fonts are present.
set -euo pipefail

image="${1:?usage: $0 <image>}"

docker run --rm --entrypoint /bin/sh "$image" -c '
  set -eu
  test -x /app/main
  test -f /app/frontend/out/index.html

  for bin in ffmpeg gs convert; do
    command -v "$bin" >/dev/null 2>&1 || {
      echo "missing runtime binary: $bin" >&2
      exit 1
    }
  done

  test -f /usr/local/share/fonts/harmonyos/HarmonyOS_Sans_Regular.ttf
  test -f /usr/local/share/fonts/harmonyos/HarmonyOS_Sans_SC_Regular.ttf

  # The app is started with this preload; make sure the soname resolves.
  LD_PRELOAD=libmimalloc.so.3 /bin/true

  missing="$(ldd /app/main | grep "not found" || true)"
  if [ -n "$missing" ]; then
    echo "missing shared libraries:" >&2
    echo "$missing" >&2
    exit 1
  fi

  echo "image smoke test passed"
'
