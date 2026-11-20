#!/usr/bin/env bash
# Verify that the runtime image can actually start the bundled binary:
# every NEEDED library resolves, the external tools and fonts are present.
set -euo pipefail

image="${1:?usage: $0 <image>}"

docker run --rm -i --entrypoint /bin/sh "$image" -s <<'SMOKE'
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

  missing="$(ldd /app/main 2>&1 | grep ' => not found' || true)"
  if [ -n "$missing" ]; then
    echo "missing shared libraries:" >&2
    echo "$missing" >&2
    echo "runtime RocksDB packages:" >&2
    dpkg-query -W -f='${binary:Package}\t${Version}\n' 'librocksdb*' >&2 2>/dev/null || true
    find /usr/lib /lib -name 'librocksdb.so*' -print >&2 2>/dev/null || true
    case "$missing" in
      *librocksdb*)
        echo "The bundled main binary was linked against a different librocksdb ABI." >&2
        echo "Build it in the same Ubuntu snapshot used by this runtime image; do not" >&2
        echo "symlink across incompatible RocksDB sonames." >&2
        ;;
    esac
    exit 1
  fi

  rocksdb_link="$(ldd /app/main 2>/dev/null | grep -i rocksdb || true)"
  printf 'linked RocksDB library: %s\n' "${rocksdb_link:-not found}"
  echo "image smoke test passed"
SMOKE
