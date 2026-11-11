#!/usr/bin/env bash
# lpack-linux：把「壳可执行文件 + 引擎库 + 非系统私有库」打成 .deb。
#
# 计划 §4.4 / §9.4：打包逻辑归属本包，CI 只负责调用（M3W 迁移目标）。
#
# 用法：
#   bash packages/lpack-linux/tools/build-deb.sh \
#       --binary <可执行文件> [--lib <额外库>...] [--icon <png>] \
#       [--version <版本>] [--depends "<apt 依赖>"] [--out <目录>]
#   bash packages/lpack-linux/tools/build-deb.sh --self-test
#
# 设计要点：
# - 只捆绑 **非系统库**（/usr、/lib、/lib64 下的靠 Depends 声明），避免把 glibc 打进包里；
# - appdir 固定 /opt/<pkgname>，用 wrapper 脚本设 LD_LIBRARY_PATH 启动；
# - .desktop 的 StartupWMClass 必须与壳上报的 app_id 一致（Wayland 任务栏图标依赖它）。
set -euo pipefail

PKGNAME=${PKGNAME:-lanlu-client-next}
ARCH=${ARCH:-amd64}
VERSION="0.1.0+nightly.$(date -u +%Y%m%d.%H%M)"
OUT=dist
DEPENDS="libvips42t64 | libvips42, libvlc5, libfontconfig1, libfreetype6"
BINARY=""
ICON=""
EXTRA_LIBS=()

die() { echo "error: $*" >&2; exit 1; }

need_dpkg() { command -v dpkg-deb >/dev/null || die "需要 dpkg-deb（sudo apt install dpkg）"; }

self_test() {
  # 用一个假二进制把整条打包链路跑通（CI 之外也能验证脚本本身）。
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "${tmp:-}"' RETURN
  printf '#!/bin/sh\necho fake\n' > "$tmp/fakebin"; chmod 755 "$tmp/fakebin"
  BINARY="$tmp/fakebin"; VERSION="0.1.0+selftest"; OUT="$tmp/dist"
  package
  ls "$OUT"/*.deb >/dev/null || die "自检没有产出 .deb"
  local inside; inside=$(dpkg-deb -c "$OUT"/*.deb | wc -l)
  [ "$inside" -gt 0 ] || die "deb 内容为空"
  echo "[PASS] 自检：生成了 $(basename "$OUT"/*.deb)（$inside 个条目）"
}

package() {
  need_dpkg
  [ -n "$BINARY" ] || die "必须给 --binary"
  [ -f "$BINARY" ] || die "找不到可执行文件：$BINARY"

  local staging="$OUT/${PKGNAME}_${VERSION}_${ARCH}"
  local appdir="$staging/opt/$PKGNAME"
  rm -rf "$staging"
  mkdir -p "$staging/DEBIAN" "$appdir" "$staging/usr/bin" "$OUT"

  cp "$BINARY" "$appdir/$PKGNAME"

  # 捆绑非系统私有库
  if command -v ldd >/dev/null; then
    ldd "$appdir/$PKGNAME" 2>/dev/null | awk '$3 ~ /^\// {print $3}' | sort -u > "$OUT/ldd.txt" || true
    while IFS= read -r lib; do
      [ -n "$lib" ] || continue
      case "$lib" in
        /usr/*|/lib/*|/lib64/*) ;;
        *) cp -L "$lib" "$appdir/" 2>/dev/null || true ;;
      esac
    done < "$OUT/ldd.txt"
  fi
  # 兜底：ldd 解析不到仓颉运行时的时候，从 CANGJIE_HOME 里找（CI 的 setup-cangjie 会导出）
  if ! ls "$appdir"/libcangjie-runtime.so* >/dev/null 2>&1; then
    if [ -n "${CANGJIE_HOME:-}" ]; then
      find "$CANGJIE_HOME" -name 'libcangjie-runtime.so*' -exec cp -L {} "$appdir/" \; -quit 2>/dev/null || true
    fi
  fi

  for l in "${EXTRA_LIBS[@]:-}"; do
    [ -n "$l" ] || continue
    cp -L "$l" "$appdir/" || die "复制库失败：$l"
  done

  # wrapper：设 LD_LIBRARY_PATH 后启动（库都在 /opt 下）
  printf '%s\n' \
    '#!/bin/sh' \
    "exec env LD_LIBRARY_PATH=\"/opt/$PKGNAME\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\" \"/opt/$PKGNAME/$PKGNAME\" \"\$@\"" \
    > "$staging/usr/bin/$PKGNAME"
  chmod 755 "$staging/usr/bin/$PKGNAME"

  # 桌面入口与图标
  mkdir -p "$staging/usr/share/applications"
  printf '%s\n' \
    '[Desktop Entry]' \
    'Type=Application' \
    'Name=Lanlu' \
    'Comment=Lanlu desktop client' \
    "Exec=/usr/bin/$PKGNAME" \
    'Icon=lanlu' \
    'StartupWMClass=lanlu' \
    'Terminal=false' \
    'Categories=Graphics;' \
    > "$staging/usr/share/applications/lanlu.desktop"
  if [ -n "$ICON" ] && [ -f "$ICON" ]; then
    mkdir -p "$staging/usr/share/icons/hicolor/192x192/apps"
    cp "$ICON" "$staging/usr/share/icons/hicolor/192x192/apps/lanlu.png"
  fi

  local installed; installed=$(du -sk "$staging" | cut -f1)
  printf '%s\n' \
    "Package: $PKGNAME" \
    "Version: $VERSION" \
    "Architecture: $ARCH" \
    "Maintainer: lanlu <lanlu@localhost>" \
    "Installed-Size: $installed" \
    "Depends: $DEPENDS" \
    "Section: graphics" \
    "Priority: optional" \
    "Description: Lanlu desktop client built on CangjieGUI" \
    > "$staging/DEBIAN/control"

  dpkg-deb --build --root-owner-group "$staging" "$OUT/${PKGNAME}_${VERSION}_${ARCH}.deb" >/dev/null
  echo "[PASS] 产出 $OUT/${PKGNAME}_${VERSION}_${ARCH}.deb"
}

main() {
  if [ "${1:-}" = "--self-test" ]; then self_test; return 0; fi
  while [ $# -gt 0 ]; do
    case "$1" in
      --binary) BINARY=$2; shift 2 ;;
      --lib) EXTRA_LIBS+=("$2"); shift 2 ;;
      --icon) ICON=$2; shift 2 ;;
      --version) VERSION=$2; shift 2 ;;
      --depends) DEPENDS=$2; shift 2 ;;
      --out) OUT=$2; shift 2 ;;
      *) die "未知参数：$1" ;;
    esac
  done
  package
}

main "$@"
