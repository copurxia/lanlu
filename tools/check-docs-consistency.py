#!/usr/bin/env python3
"""文档一致性守卫：文档里写的数字/引用必须与仓库真实状态一致。

为什么需要：多轮里出现过"文档说 X、实际是 Y"（协议消息数、文件桥处数、行号引用）。
数字漂移不会让测试变红，但会让下一个人照着过期信息行动。

检查项：
1. 协议消息数/接口数（仅"当前状态类"文档）；
2. 文件桥处数（仅提到"文件桥"的行）；
3. 代码行号引用（`file.cpp:123`）：文件存在且行号未越界；
4. 相对链接目标存在。
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"

# 只对"当前状态类"文档校验数字；进度日志里的历史数字本来就该不同。
CURRENT_DOCS = {
    "lwp-acceptance-report.md",
    "lwp-handoff-status.md",
    "lwindow-platform-separation-plan.md",
    "lwp-known-limitations.md",
}

# apps/ 在迁移期间逐步填充；现在加入是为了 PR2–PR6 搬完后不静默失去校验能力。
SOURCE_DIRS = ["packages", "apps", "client-next/src", "tools", "docs"]
SKIP_PARTS = {"target", "build", "node_modules", ".git", ".research-ohos"}
CODE_SUFFIXES = {".cj", ".rs", ".cpp", ".ets", ".c", ".h"}

_INDEX: dict[str, Path] | None = None


def file_index() -> dict[str, Path]:
    """一次性建立「文件名 -> 路径」索引（跳过构建产物目录）。

    对每个引用单独 rglob 会扫到 target/ 下几十万文件，实测把检查拖到超时。
    """
    global _INDEX
    if _INDEX is not None:
        return _INDEX
    idx: dict[str, Path] = {}
    for d in SOURCE_DIRS:
        base = ROOT / d
        if not base.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [n for n in dirnames if n not in SKIP_PARTS]
            for name in filenames:
                if Path(name).suffix in CODE_SUFFIXES:
                    idx.setdefault(name, Path(dirpath) / name)
    _INDEX = idx
    return idx


def resolve_source(name: str) -> Path | None:
    direct = ROOT / name
    if direct.is_file():
        return direct
    return file_index().get(Path(name).name)


def protocol_counts() -> tuple[int, int]:
    out = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "lwp-gen.py"), "--check"],
        capture_output=True, text=True,
    )
    m = re.search(r"(\d+) 条消息，(\d+) 个接口", out.stdout)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def file_bridge_count() -> int:
    out = subprocess.run(
        ["bash", str(ROOT / "tools" / "check-no-file-bridge.sh")],
        capture_output=True, text=True,
    )
    m = re.search(r"(\d+) 处", out.stdout)
    return int(m.group(1)) if m else -1


def main() -> int:
    msgs, ifaces = protocol_counts()
    bridges = file_bridge_count()
    problems: list[str] = []

    for md in sorted(DOCS.glob("*.md")):
        text = md.read_text(encoding="utf-8", errors="replace")
        rel = md.relative_to(ROOT)
        # 只看本计划相关的文档（lwp-* / lwindow-*）；仓库里其它历史文档不在范围内
        if not md.name.startswith(("lwp-", "lwindow-")):
            continue
        is_current = md.name in CURRENT_DOCS

        if is_current:
            for m in re.finditer(r"(\d+)\s*条消息(?:，| / )(\d+)\s*个接口", text):
                if (int(m.group(1)), int(m.group(2))) != (msgs, ifaces):
                    problems.append(
                        f"{rel}: 写 {m.group(1)} 条消息 / {m.group(2)} 个接口，"
                        f"实际 {msgs} / {ifaces}"
                    )
            for line in text.splitlines():
                if "文件桥" not in line:
                    continue
                for m in re.finditer(r"(\d+)\s*→\s*(\d+)", line):
                    before, after = int(m.group(1)), int(m.group(2))
                    if before > after and after != bridges:
                        problems.append(f"{rel}: 写 {before} → {after}，实际现状 {bridges}")

        # 代码行号引用（`file.cpp:123`）：仅当前状态文档必须指向现存文件。
        # 进度日志是历史记录，允许引用已删除的文件。
        for m in (re.finditer(r"([A-Za-z0-9_./-]+\.(?:cj|rs|cpp|ets|c|h)):(\d+)", text)
                   if is_current else []):
            target = resolve_source(m.group(1))
            if target is None:
                problems.append(f"{rel}: 行号引用的文件不存在：{m.group(1)}")
                continue
            n = len(target.read_text(encoding="utf-8", errors="replace").splitlines())
            if int(m.group(2)) > max(n, 1):
                problems.append(f"{rel}: {m.group(1)}:{m.group(2)} 超出文件行数（共 {n} 行）")

        # 2c) 文档里给出的脚本路径必须存在（bash/py/sh 调用）
        for m in re.finditer(r"\b(?:bash|python3|sh)\s+(packages/[\w./-]+\.(?:sh|py)|tools/[\w.-]+\.(?:sh|py))", text):
            if not (ROOT / m.group(1)).exists():
                problems.append(f"{rel}: 命令里引用的脚本不存在：{m.group(1)}")

        # 相对链接（先剥掉行内代码，避免文档里举例的 `](path)` 误报）
        stripped = re.sub(r"`[^`\n]*`", "", text)
        for m in re.finditer(r"\]\((?!https?:|#|mailto:)([^)#]+)", stripped):
            if not (md.parent / m.group(1)).resolve().exists():
                problems.append(f"{rel}: 链接目标不存在：{m.group(1)}")

    if problems:
        print(f"[FAIL] 文档一致性：{len(problems)} 处不一致")
        for p in problems[:20]:
            print(f"  - {p}")
        return 1
    print(f"[PASS] 文档一致（协议 {msgs} 条 / {ifaces} 接口，文件桥 {bridges} 处）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
