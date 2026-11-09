#!/usr/bin/env bash
# 生成 "SONAME = libSDL3.so" 的 SDL3 前缀（prefix-nov）。
#
# 为什么需要：SDL3 的 SONAME 是 libSDL3.so.0，而 libSDL3_ttf.so 等下游库是按
# libSDL3.so 这个文件名依赖的。两者同时存在时，进程里会加载**两份 SDL3**：
# 引擎初始化一份、壳(libmain)拿到另一份未初始化的 -> 窗口动作/文件对话框钩子注册到
# 错误实例、SDL_PushEvent 恒失败（IME 文本投递不了）。
#
# 把 SONAME 原地改短为 libSDL3.so 后，壳/引擎/ttf 的 DT_NEEDED 全部一致，
# 打包只需一份库，进程里只有一个 SDL3 实例。
set -euo pipefail
RES=${RES:-/workspace/lanlu/.research-ohos}
SRC="$RES/sdl3-ohos/prefix-single"
DST="$RES/sdl3-ohos/prefix-nov"
mkdir -p "$DST/lib"
ln -sfn "$SRC/include" "$DST/include"
cp -f "$SRC/lib/libSDL3.so.0.5.0" "$DST/lib/libSDL3.so"
python3 - "$DST/lib/libSDL3.so" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
d = p.read_bytes()
old, new = b'libSDL3.so.0\x00', b'libSDL3.so\x00\x00\x00'
hits = d.count(old)
p.write_bytes(d.replace(old, new))
print('patched SONAME occurrences:', hits)
PY
readelf -d "$DST/lib/libSDL3.so" | grep SONAME
