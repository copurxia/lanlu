#!/usr/bin/env python3
"""检查"每帧写状态"陷阱（真机空闲 60fps 空转的根因类）。

背景：State.set **即使赋相同值也会**推进 stateWriteGeneration（脏帧判据），
所以在 UiEvent.Frame 处理里无条件写 .value = ... 会让渲染循环每帧都判定"脏"，
空闲也满帧重绘（实测 60fps，基线应为 0）。

规则：Frame 分支里的 .value 赋值必须处于条件分支内（if/match 分支体），
或文件里显式加入 ALLOW（一次性语义，例如 autofocusDone）。
"""
import re, sys, pathlib

ROOTS = ["client-next/src", "packages/cangjie-gui/src"]
WRITE = re.compile(r"\.value\s*=")
FRAME = re.compile(r"UiEvent\.Frame")

# 允许的无条件写法：key 形如 "相对路径:行内容片段"，需人工确认是一次性写入
ALLOW = {
    "autofocusDone.value = true",   # 由 if (autofocusRequested && !autofocusDone.value) 守护
}

def scan(root: pathlib.Path):
    bad = []
    for p in root.rglob("*.cj"):
        if "_test" in p.name:
            continue
        lines = p.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            if not FRAME.search(line):
                continue
            base = len(line) - len(line.lstrip())
            j = i + 1
            while j < len(lines):
                cur = lines[j]
                if cur.strip() == "":
                    j += 1
                    continue
                ind = len(cur) - len(cur.lstrip())
                if ind <= base:
                    break
                if WRITE.search(cur):
                    # 往上找最近的更低缩进行：必须是 if/match/case 之类的条件体
                    guarded = False
                    k = j - 1
                    while k > i:
                        prev = lines[k]
                        if prev.strip() == "":
                            k -= 1
                            continue
                        pind = len(prev) - len(prev.lstrip())
                        if pind < ind:
                            head = prev.strip()
                            if head.startswith("if ") or head.startswith("if(") or head.startswith("case ") \
                               or head.startswith("} else") or head.startswith("else if"):
                                guarded = True
                            break
                        k -= 1
                    text = cur.strip()
                    if not guarded and not any(a in text for a in ALLOW):
                        bad.append((str(p), j + 1, text))
                j += 1
    return bad

def main():
    bad = []
    for r in ROOTS:
        root = pathlib.Path(r)
        if root.exists():
            bad += scan(root)
    if bad:
        print("[FAIL] 发现每帧无条件写 State（会把渲染循环钉在满帧）：")
        for p, n, t in bad:
            print("  %s:%d  %s" % (p, n, t))
        print("  修法：改成 'if (旧值 != 新值) { 写入 }'，或确认一次性后加进 ALLOW。")
        return 1
    print("[PASS] 无每帧无条件写 State")
    return 0

if __name__ == "__main__":
    sys.exit(main())
