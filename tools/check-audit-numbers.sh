#!/usr/bin/env bash
# 审计一致性校验（只读，不修改任何文件）：
#   1) 当前面向文档的数字（提交数 / 补丁数）是否与实际一致——历史叙述（"当时 N 个"）不参与；
#   2) 框架文档树与审计文档树的相对内链是否全部可达；
#   3) 覆盖矩阵引用的测试名是否都能在 src/lgui 的 *_test.cj 里找到。
# 一条命令确认"文档没有说谎、没有死链、没有引用不存在的测试"。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUI="$ROOT/packages/cangjie-gui-p0"
[ -d "$GUI/.git" ] || { echo "跳过：$GUI 已不是 git 工作树（cangjie-gui 已收编）"; exit 0; }

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

# 4b) 交付索引头部与摘要测试行（叙述性状态，最容易过期）。
readme_hdr=$(grep -oE '[0-9]+ 提交 / [0-9]+ 测试通过' "$ROOT/docs/interaction-audit/README.md" | head -1 | grep -oE '^[0-9]+')
[ "${readme_hdr:-x}" = "$COMMITS" ] || { echo "✗ 审计 README 头部写的是 ${readme_hdr:-?} 提交，实际 $COMMITS"; fail=1; }
grep -q '例 / [0-9]* 通过' "$ROOT/docs/interaction-audit/01-summary.md" || { echo "✗ 01-summary 缺测试行"; fail=1; }
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
# 5b) 示例 README 不得提及已从框架移除的 API（目前黑名单：Surface——随 SDL 移除）。
# 示例自有类型（CalcModel 等）定义在示例 src 里，不在此检查范围。
EXDIR="$GUI/examples"
REMOVED_APIS="Surface"
if [ -d "$EXDIR" ]; then
  while IFS= read -r f; do
    for name in $REMOVED_APIS; do
      if grep -qE "\`$name\`" "$f" 2>/dev/null; then
        echo "✗ 示例 README 提及已移除的 API：$name（$f）"
        fail=1
      fi
    done
  done < <(find "$EXDIR" -name 'README.md' -maxdepth 2)
fi

check_links "$ROOT/docs/interaction-audit" || fail=1

# 6) 覆盖矩阵里引用的测试名必须能在 src/ 或 lgui/ 的 *_test.cj 里找到。
#    例外：应用侧的 readerHtmlPageTurn（矩阵里本就标注"仅人工"）。
MATRIX="$ROOT/docs/interaction-audit/08-coverage-matrix.md"
if [ -f "$MATRIX" ]; then
  miss=0
  for name in $(grep -oE '`[a-z][A-Za-z0-9]+`' "$MATRIX" | tr -d '`' | sort -u); do
    # 若该标识符其实是源码里的类型/函数/变量（例如 pixelMaxImageSide），说明矩阵在叙述实现
    # 而不是引用测试——跳过，避免把实现名当成测试名。
    if grep -rqE "(func|class|struct|enum|interface|var|let|prop) $name\b" --include='*.cj' "$GUI/src" "$GUI/lgui" 2>/dev/null; then
      continue
    fi
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
