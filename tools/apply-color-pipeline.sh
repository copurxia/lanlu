#!/usr/bin/env bash
# 把「色彩管线（方案 C）+ 主题测试钩子 + 弹窗模糊」补丁应用到当前检出并验证。
#
# 为什么需要脚本：这三项是**原子改动**，分散合入会得到错误画面：
#   - 只改 canvas.cj（直传）而不加 blit  → 整体偏暗
#   - 只加 blit 而 canvas 仍预解码        → 整体过曝（回到修复前）
# 脚本会校验补丁集完整性后一次性应用。
#
# 用法：
#   bash tools/apply-color-pipeline.sh            # 应用补丁
#   bash tools/apply-color-pipeline.sh --verify   # 应用 + 构建
#   bash tools/apply-color-pipeline.sh --revert   # 撤销
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATCH_DIR=${PATCH_DIR:-/workspace/lanlu/tmp/color-patches}
MODE=${1:-apply}

need=(0001 0002 0006)   # 核心三项：方案C、主题钩子、模糊 48px
for n in "${need[@]}"; do
  ls "$PATCH_DIR/$n"-*.patch >/dev/null 2>&1 || {
    echo "[FAIL] 缺少补丁 $n（目录 $PATCH_DIR）" >&2; exit 1; }
done

case "$MODE" in
  --revert)
    for f in $(ls -r "$PATCH_DIR"/*.patch); do
      git -C "$ROOT" apply -R --3way "$f" 2>/dev/null && echo "  revert $(basename "$f")" || true
    done
    echo "[OK] 已尝试撤销"
    ;;
  apply|--verify)
    for f in $(ls "$PATCH_DIR"/*.patch | sort); do
      if git -C "$ROOT" apply --3way "$f" 2>/dev/null; then
        echo "  applied $(basename "$f")"
      else
        echo "  [SKIP] $(basename "$f")（已在或冲突，需手工确认）"
      fi
    done
    # cangjie-gui 不入 git，模糊改动需直接改文件
    python3 - "$ROOT" <<'PY'
import sys, pathlib
root = pathlib.Path(sys.argv[1])
p = root / 'packages/cangjie-gui/src/controls/modal.cj'
s = p.read_text(encoding='utf-8')
if 'sigma: 12.0' in s:
    print('  modal 模糊已是 48px')
elif 'captureBlurredTexture(4, sigma: 4.0)' in s:
    p.write_text(s.replace('captureBlurredTexture(4, sigma: 4.0)',
                           'captureBlurredTexture(4, sigma: 12.0)'), encoding='utf-8')
    print('  modal 模糊 16px → 48px')
else:
    print('  [WARN] modal.cj 未找到模糊调用，需手工确认')
PY
    # 原子性校验：canvas 直传 + lib.rs 有 blit 必须同时成立
    if grep -q 'func channel(v: UInt8): Float32 {' "$ROOT/packages/lgpu/src/canvas.cj" &&
       grep -q 'SRGB_TO_LINEAR' "$ROOT/packages/lgpu/src/canvas.cj" &&
       grep -q 'lgpu-blit-pass' "$ROOT/packages/lgpu/native/src/lib.rs"; then
      echo "[FAIL] 组合非法：canvas 仍预解码 + 已加 blit → 会整体过曝" >&2; exit 1
    fi
    if ! grep -q 'lgpu-blit-pass' "$ROOT/packages/lgpu/native/src/lib.rs" &&
       ! grep -q 'SRGB_TO_LINEAR' "$ROOT/packages/lgpu/src/canvas.cj"; then
      echo "[FAIL] 组合非法：既无 blit 也无预解码 → 会整体过曝" >&2; exit 1
    fi
    echo "[OK] 色彩管线组合自洽"
    if [ "$MODE" = "--verify" ]; then
      bash "$ROOT/packages/lpack-ohos/tools/build-ohos.sh"
    fi
    ;;
  *) echo "未知参数 $MODE（支持 apply / --verify / --revert）" >&2; exit 2 ;;
esac
