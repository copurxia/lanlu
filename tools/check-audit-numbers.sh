#!/usr/bin/env bash
# 审计一致性校验（只读，不修改任何文件）：
#   1) 当前面向文档的数字（提交数 / 补丁数）是否与实际一致——历史叙述（"当时 N 个"）不参与；
#   2) 框架文档树与审计文档树的相对内链是否全部可达；
#   3) 覆盖矩阵引用的测试名是否都能在 src/lgui 的 *_test.cj 里找到。
# 一条命令确认"文档没有说谎、没有死链、没有引用不存在的测试"。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUI="$ROOT/packages/cangjie-gui-p0"
[ -d "$GUI" ] || { echo "跳过：找不到 $GUI"; exit 0; }

COMMITS=$(git -C "$GUI" rev-list --count c39458f..HEAD)
PATCHES=$(ls "$ROOT/docs/interaction-audit/patches"/*.patch 2>/dev/null | wc -l)
PASSED=$(grep -hoE 'PASSED: [0-9]+' "$ROOT"/docs/interaction-audit/*.md | tail -1 | grep -oE '[0-9]+')
echo "实际：提交 $COMMITS / 补丁 $PATCHES"

fail=0
# 1) 补丁 README 的"全部 N 个提交"
readme_n=$(grep -oE '\*\*[0-9]+ 个补丁 = 分支全部 [0-9]+ 个提交\*\*' "$ROOT/docs/interaction-audit/patches/README.md" | grep -oE '[0-9]+ 个提交' | grep -oE '[0-9]+')
[ "${readme_n:-x}" = "$COMMITS" ] || { echo "✗ patches/README.md 写的是 ${readme_n:-?} 个提交，实际 $COMMITS"; fail=1; }
# 2) 09 状态表头
s09=$(grep -oE '\*\*[0-9]+ 个提交\*\*' "$ROOT/docs/interaction-audit/09-gap-final-status.md" | head -1 | grep -oE '[0-9]+')
[ "${s09:-x}" = "$COMMITS" ] || { echo "✗ 09-gap-final-status.md 写的是 ${s09:-?} 个提交，实际 $COMMITS"; fail=1; }
# 3) RC 报告的补丁数
rc=$(grep -oE '\*\*[0-9]+ 个补丁\*\*' "$ROOT/docs/interaction-audit/11-rc-report.md" | head -1 | grep -oE '[0-9]+')
[ "${rc:-x}" = "$PATCHES" ] || { echo "✗ 11-rc-report.md 写的是 ${rc:-?} 个补丁，实际 $PATCHES"; fail=1; }
# 4) 01-summary 的实现行提交数
sm=$(grep -oE '\*\*[0-9]+ 个提交（' "$ROOT/docs/interaction-audit/01-summary.md" | head -1 | grep -oE '[0-9]+')
[ "${sm:-x}" = "$COMMITS" ] || { echo "✗ 01-summary.md 写的是 ${sm:-?} 个提交，实际 $COMMITS"; fail=1; }

# 5) 文档内链：两棵树全部 .md 的相对链接必须可达（http 除外）。
check_links() {
  local dir="$1"
  python3 - "$dir" <<'PY'
import os, re, sys
root = sys.argv[1]
bad = []
for sub, _, files in os.walk(root):
    for f in files:
        if not f.endswith('.md'):
            continue
        p = os.path.join(sub, f)
        t = open(p, encoding='utf-8').read()
        for m in re.finditer(r'\[[^\]]+\]\(([^)#\s]+)(?:#[^)]*)?\)', t):
            u = m.group(1)
            if u.startswith('http'):
                continue
            target = os.path.normpath(os.path.join(sub, u))
            if not os.path.exists(target):
                bad.append((os.path.relpath(p, root), u))
if bad:
    for b in bad[:10]:
        print("✗ 断链 %s → %s" % b)
    sys.exit(1)
PY
}
check_links "$ROOT/packages/cangjie-gui-p0/docs" || fail=1
check_links "$ROOT/docs/interaction-audit" || fail=1

# 6) 覆盖矩阵里引用的测试名必须能在 src/ 或 lgui/ 的 *_test.cj 里找到。
#    例外：应用侧的 readerHtmlPageTurn（矩阵里本就标注"仅人工"）。
MATRIX="$ROOT/docs/interaction-audit/08-coverage-matrix.md"
if [ -f "$MATRIX" ]; then
  miss=0
  for name in $(grep -oE '`[a-z][A-Za-z0-9]+`' "$MATRIX" | tr -d '`' | sort -u); do
    if ! grep -rq "func $name" --include='*_test.cj' "$GUI/src" "$GUI/lgui" 2>/dev/null; then
      [ "$name" = "readerHtmlPageTurn" ] && continue   # 应用侧，标注仅人工
      echo "✗ 覆盖矩阵引用了不存在的测试：$name"
      miss=1
    fi
  done
  [ "$miss" -eq 0 ] || fail=1
fi

[ "$fail" -eq 0 ] && echo "== 审计一致性通过：数字（提交 $COMMITS / 补丁 $PATCHES）+ 两棵树文档内链 + 覆盖矩阵测试名"
exit "$fail"
