#!/usr/bin/env bash
# 复现 cui 交互审计的测试基线（无需 GPU/SDL 设备）。
#
# 背景：本机没有 libvips / libSDL3 的 x86 共享库，`cjpm test` 链接期会失败。
# 本脚本生成两个"符号齐全、恒空实现"的桩库，再用 `LIBRARY_PATH` 让 ld 找到它们；
# 测试不涉及图片编解码与真实窗口，桩函数不会被业务逻辑调用。
#
# 用法：
#   tools/verify-cui-interactions.sh                # 测试主仓 packages/cangjie-gui
#   tools/verify-cui-interactions.sh p0             # 测试 p0-focus-visible 工作树
#
# 可移植性：默认路径（工具链 /workspace/.cjv、桩库 /workspace/tmp、日志 /workspace/tmp）
# 都可用环境变量覆盖——CJV / STUB / LOG / PKG_DIR，脚本内全部写作 ${VAR:-默认} 形式。
# 基线名册见 docs/interaction-audit/test-baseline-names.txt（每条的豁免依据见 test-baseline-notes.md）：
# 名册共 7 条 = 6 个 headless 绘制/SDL/文本度量依赖 ERROR + 1 个真实 wake 事件 FAILED
# （pushWakeEventWakesWaitingLoopFromAnotherThread）。
# 本脚本会比对完整失败名册；只有名单与基线完全一致才返回 0，新增/消失测试失败都会报错。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TREE="${1:-main}"
case "$TREE" in
  p0|branch) PKG="$ROOT/packages/cangjie-gui-p0" ;;
  main|*)    PKG="$ROOT/packages/cangjie-gui" ;;
esac
# 自定义工程目录（例如合并演练副本）：显式路径优先于上面的预设。
if [ -n "${PKG_DIR:-}" ]; then
  PKG="$PKG_DIR"
fi

CJV="${CJV:-/workspace/.cjv}"
STUB="${STUB:-/workspace/tmp/cui-test-stubs}"

if [ ! -x "$CJV/bin/cjc" ]; then
  echo "找不到仓颉工具链：$CJV/bin/cjc（可用 CJV=... 指定）" >&2
  exit 2
fi
if [ ! -d "$PKG" ]; then
  echo "找不到工程目录：$PKG" >&2
  echo "（p0 工作树需先执行：git -C packages/cangjie-gui worktree add ../cangjie-gui-p0 -b p0-focus-visible）" >&2
  exit 2
fi

mkdir -p "$STUB"
cat > "$STUB/stub.c" <<'EOF'
/* 仅供本机链接/运行 cui 单元测试的桩：符号齐全、恒失败返回。 */
#include <stddef.h>
typedef struct _VipsImage VipsImage;
int vips_init(const char *a) { (void)a; return 0; }
void vips_shutdown(void) {}
const char *vips_error_buffer(void) { return "stub"; }
void vips_error_clear(void) {}
VipsImage *vips_image_new_from_file(const char *f, ...) { (void)f; return NULL; }
VipsImage *vips_image_new_from_memory_copy(const void *d, size_t s, int w, int h, int b, int fmt) {
  (void)d; (void)s; (void)w; (void)h; (void)b; (void)fmt; return NULL;
}
int vips_image_get_width(const VipsImage *i) { (void)i; return 0; }
int vips_image_get_height(const VipsImage *i) { (void)i; return 0; }
int vips_image_get_bands(const VipsImage *i) { (void)i; return 0; }
int vips_autorot(VipsImage *i, VipsImage **o, ...) { (void)i; (void)o; return -1; }
int vips_resize(VipsImage *i, VipsImage **o, double s, ...) { (void)i; (void)o; (void)s; return -1; }
int vips_gaussblur(VipsImage *i, VipsImage **o, double s, ...) { (void)i; (void)o; (void)s; return -1; }
int vips_extract_area(VipsImage *i, VipsImage **o, int l, int t, int w, int h, ...) {
  (void)i; (void)o; (void)l; (void)t; (void)w; (void)h; return -1;
}
int vips_extract_band(VipsImage *i, VipsImage **o, int b, ...) { (void)i; (void)o; (void)b; return -1; }
int vips_text(VipsImage **o, const char *t, ...) { (void)o; (void)t; return -1; }
int vips_colourspace(VipsImage *i, VipsImage **o, int s, ...) { (void)i; (void)o; (void)s; return -1; }
int vips_cast_uchar(VipsImage *i, VipsImage **o, ...) { (void)i; (void)o; return -1; }
int vips_bandjoin_const1(VipsImage *i, VipsImage **o, double c, ...) { (void)i; (void)o; (void)c; return -1; }
int vips_bandjoin(VipsImage **i, VipsImage **o, int n, ...) { (void)i; (void)o; (void)n; return -1; }
int vips_image_write_to_file(VipsImage *i, const char *f, ...) { (void)i; (void)f; return -1; }
void *vips_image_write_to_memory(VipsImage *i, size_t *s) { (void)i; (void)s; return NULL; }
void g_object_unref(void *o) { (void)o; }
void g_free(void *m) { (void)m; }
void vips_concurrency_set(int n) { (void)n; }
EOF

# SDL3/TTF 符号：先给一份固定的已知清单（干净工作树/全新副本没有 target/ 可扫描时也能链接），
# 再叠加当前 target 里实际未解析的符号（分支演进新增调用时自动兜住）。
KNOWN_SDL="SDL_CaptureMouse SDL_ConvertSurface SDL_CreateSurfaceFrom SDL_CreateTexture SDL_CreateTextureFromSurface SDL_DestroyRenderer SDL_DestroySurface SDL_DestroyWindow SDL_GetModState SDL_GetMouseState SDL_GetPathInfo SDL_GetTextureSize SDL_GetTicks SDL_GlobDirectory SDL_Quit SDL_RenderClear SDL_RenderGeometry SDL_RenderReadPixels SDL_SetHintWithPriority SDL_SetRenderClipRect SDL_SetRenderDrawBlendMode SDL_SetRenderScale SDL_SetRenderTarget SDL_SetRenderVSync SDL_ShowMessageBox SDL_ShowOpenFileDialog SDL_ShowOpenFolderDialog SDL_ShowSaveFileDialog SDL_ShowSimpleMessageBox SDL_UpdateTexture SDL_free"
DISCOVERED="$(cd "$PKG" && { find target -name '*.a' -print0 2>/dev/null | xargs -0 nm -uA 2>/dev/null || true; } \
  | awk '{print $NF}' | grep -E '^(SDL_|TTF_)' || true)"
SYMS="$( { printf '%s\n' $KNOWN_SDL; printf '%s\n' "$DISCOVERED"; } | grep -E '^(SDL_|TTF_)' | sort -u)"
{ echo '#include <stdint.h>'; printf '%s\n' "$SYMS" | sed 's/.*/void &(void) {}/'; } >> "$STUB/stub.c"

gcc -shared -fPIC -o "$STUB/libvips.so" "$STUB/stub.c"

echo "== 桩库：$STUB/libvips.so（$(nm -D --defined-only "$STUB/libvips.so" | wc -l) 个符号）"
echo "== 工程：$PKG"

cd "$PKG"
export PATH="$CJV/bin:$PATH"
export LIBRARY_PATH="$STUB"
export LD_LIBRARY_PATH="$STUB"
LOG="${LOG:-/workspace/tmp/cui-interactions-${TREE}.log}"
set +e
cjpm test > "$LOG" 2>&1
RC=$?
set -e
CLEAN="$(mktemp)"
sed 's/\x1b\[[0-9;]*m//g' "$LOG" > "$CLEAN"
sed -nE 's/.*(\[ ERROR  \] CASE:|\[ FAILED \] CASE:) ([A-Za-z0-9_]+).*/\2/p' "$CLEAN" | sort -u > "$STUB/failures.actual"
sort "$ROOT/docs/interaction-audit/test-baseline-names.txt" > "$STUB/failures.expected"
sed -nE '/^Summary: TOTAL|^    PASSED:|^    FAILED:|^    ERROR:/p' "$CLEAN" | tail -4
if diff -u "$STUB/failures.expected" "$STUB/failures.actual"; then
  echo "== 基线匹配：失败名册与 headless 基线完全一致（cjpm exit=$RC）"
else
  echo "== 回归/环境变化：失败名册与基线不同（见上方 diff）" >&2
  exit 1
fi
echo "== 日志：$LOG" 
exit 0
