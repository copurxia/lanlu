#!/usr/bin/env python3
"""平台标识守卫（计划 §4.5 / §16.2 T0）。

OS 专有标识只允许出现在平台包里：
  packages/lplatform-*    各平台壳
  packages/lpack-*        各平台工程生成/打包
  */third_party/*         上游 vendored 代码（含回馈上游的补丁）

其余位置（业务、cui、lwindow、lgpu、lwp、lbase、工具、CI）出现即违规。
与 tools/quality-baseline.toml 的 [platform] 对比，只允许下降。

用法：
  python3 tools/check-platform-isolation.py
  python3 tools/check-platform-isolation.py --report
  python3 tools/check-platform-isolation.py --update-baseline
"""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "tools" / "quality-baseline.toml"

SKIP_DIR_PARTS = {
    ".git", "target", "node_modules", ".research-ohos", "build-script-cache",
    "reports", "dist", "third_party", ".hvigor", ".cjv-tmp", ".cj-smoke",
}
SKIP_TOP_DIRS = {"docs", "build"}
SCAN_SUFFIXES = {".cj", ".rs", ".c", ".cc", ".cpp", ".h", ".hpp", ".ets",
                 ".toml", ".sh", ".json5", ".yml", ".yaml"}

# 允许出现平台代码的目录（相对仓库根）；新平台 = 新增两个包，不改这里
PLATFORM_PKG_PREFIXES = ("packages/lplatform-", "packages/lpack-")

RULES: dict[str, re.Pattern[str]] = {
    # 鸿蒙
    "ohos": re.compile(
        r"OH_[A-Z]\w*|napi_\w+|@ohos\.\w+|@kit\.\w+|\bXComponent\b"
        r"|/data/storage|/system/lib64|/system/fonts|\bmodule\.json5\b"
        r"|\bhvigor\w*|aarch64-linux-ohos"
    ),
    # Wayland / Linux 桌面
    "wayland": re.compile(
        r"\bwl_[a-z]\w*|\bxdg_[a-z]\w*|\bzwp_\w+|\bwp_[a-z]\w*|\bxkb_\w+"
        r"|XDG_SESSION_TYPE|\bWAYLAND_DISPLAY\b|org\.freedesktop|\blibdecor\b"
    ),
    # SDL：全仓禁止（M6 后对平台包也生效）
    "sdl": re.compile(r"\bSDL_\w+|\bTTF_\w+|\bSdl[A-Z]\w*"),
}

# 无意义的历史产物/生成物目录（相对路径前缀）
SKIP_REL_PREFIXES = (
    # 构建/联调脚本天生与平台绑定（它们跑在具体平台上），不属于"业务层混入平台代码"
    "tools/",
    "packages/lpack-ohos/target/",
    "packages/cangjie-gui/examples/",
    ".github/",
    ".gitea/",
)


def load_baseline_keys() -> list[str]:
    if not BASELINE.exists():
        return []
    with BASELINE.open("rb") as f:
        data = tomllib.load(f)
    return list(data.get("platform", {}).get("keys", []))


def write_baseline(platform_keys: list[str]) -> None:
    deps_keys: list[str] = []
    if BASELINE.exists():
        with BASELINE.open("rb") as f:
            deps_keys = list(tomllib.load(f).get("deps", {}).get("keys", []))
    lines = [
        "# 质量基线（计划 §16.2 T0）——由 tools/check-*.py --update-baseline 生成，勿手改。",
        "# 记录迁移起点的问题集合；数量只允许下降。清理后运行对应脚本刷新。",
        "",
    ]
    for name, keys in (("deps", deps_keys), ("platform", platform_keys)):
        lines.append(f"[{name}]")
        if keys:
            lines.append("keys = [")
            lines += [f'  "{k}",' for k in sorted(set(keys))]
            lines.append("]")
        else:
            lines.append("keys = []")
        lines.append("")
    BASELINE.write_text("\n".join(lines), encoding="utf-8")


def strip_comments(text: str, suffix: str) -> str:
    """去掉注释再匹配。

    守卫要判的是「代码里出现了平台专有标识」，不是「注释里提到了 wayland」。
    早期版本不剥注释，导致协议 IDL 里一句“对应 wl_surface”就被判违规——
    这类假阳性会逼人改写注释，反而丢失设计依据。
    """
    if suffix in (".toml", ".sh", ".yml", ".yaml", ".py"):
        out = []
        for line in text.splitlines():
            idx = line.find("#")
            if idx >= 0:
                line = line[:idx]
            # TOML 的 doc/summary 字段是文档文本（与注释同性质），不参与判违规
            stripped = line.lstrip()
            if stripped.startswith("doc ") or stripped.startswith("summary "):
                continue
            out.append(line)
        return "\n".join(out)

    out = []
    in_block = False
    for line in text.splitlines():
        if in_block:
            end = line.find("*/")
            if end < 0:
                continue
            line = line[end + 2:]
            in_block = False
        while True:
            start = line.find("/*")
            if start < 0:
                break
            end = line.find("*/", start + 2)
            if end < 0:
                line = line[:start]
                in_block = True
                break
            line = line[:start] + " " + line[end + 2:]
        idx = line.find("//")
        if idx >= 0:
            line = line[:idx]
        out.append(line)
    return "\n".join(out)


def strip_cross_target_sections(text: str) -> str:
    """去掉 cjpm.toml 里的 [target.<triple>] 段（交叉编译构建配置，与平台代码无关）。"""
    out: list[str] = []
    skipping = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and not stripped.startswith("[["):
            skipping = stripped.startswith("[target.")
        if skipping:
            continue
        out.append(line)
    return "\n".join(out)


def is_platform_pkg(rel: str) -> bool:
    return rel.startswith(PLATFORM_PKG_PREFIXES)


def scan() -> list[tuple[str, str, int]]:
    """返回 [(相对路径, 规则名, 命中数)]。用 os.walk 剪枝，避免遍历 target/ 等大目录。"""
    import os

    hits: list[tuple[str, str, int]] = []
    self_files = {
        "tools/check-platform-isolation.py",
        "tools/check-layering.sh",
        "tools/check-deps.py",
        "tools/deps-rules.toml",
        "tools/quality-baseline.toml",
        "tools/file-bridge-baseline.toml",   # 记录文件桥现状（含设备路径）的数据文件，非代码
    }
    # 只扫 git 已跟踪的目录：未跟踪的目录是工作副本/实验快照（如 cangjie-gui-p0），
    # 不属于分层承诺范围；扫它们会把临时拷贝的 SDL 绑定算成新增违规。
    import subprocess
    tracked_dirs: set[str] | None
    try:
        out = subprocess.run(["git", "ls-files"], cwd=ROOT,
                             capture_output=True, text=True, check=False).stdout
        tracked_dirs = set()
        for line in out.splitlines():
            parts = line.split("/")
            for i in range(1, len(parts)):
                tracked_dirs.add("/".join(parts[:i]))  # 含文件自身前缀
    except OSError:
        tracked_dirs = None  # 无 git 时退化为全量扫描
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel_dir = Path(dirpath).relative_to(ROOT)
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIR_PARTS]
        if not rel_dir.parts:
            dirnames[:] = [d for d in dirnames if d not in SKIP_TOP_DIRS]
        if tracked_dirs is not None:
            # 剪枝：当前目录本身未被 git 跟踪（其下无任何已跟踪文件）则整棵跳过
            rel_dir_str = rel_dir.as_posix()
            if rel_dir_str != "." and rel_dir_str not in tracked_dirs:
                continue
        for name in filenames:
            path = Path(dirpath) / name
            if path.suffix not in SCAN_SUFFIXES:
                continue
            rel = (rel_dir / name).as_posix()
            if rel in self_files or rel.startswith(SKIP_REL_PREFIXES) or is_platform_pkg(rel):
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            code = strip_comments(text, path.suffix)
            if name == "cjpm.toml":
                # 中立包的 [target.<triple>] 段是**交叉编译构建配置**（sysroot/链接参数），
                # 不是平台代码：没有任何一条 import/API 因它进入业务层。
                # 计划 §4.5 的口径：守卫判「代码里的平台标识」，构建配置单独由 §4.4 约束。
                code = strip_cross_target_sections(code)
            for rule_name, pattern in RULES.items():
                n = len(pattern.findall(code))
                if n:
                    hits.append((rel, rule_name, n))
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--update-baseline", action="store_true")
    args = ap.parse_args()

    hits = scan()
    current = {f"{rel}|{rule}" for rel, rule, _ in hits}

    if args.update_baseline:
        write_baseline(sorted(current))
        print(f"[platform] 基线已更新：{len(current)} 条")
        return 0

    if args.report:
        by_rule: dict[str, list[tuple[str, int]]] = {}
        for rel, rule, n in hits:
            by_rule.setdefault(rule, []).append((rel, n))
        for rule in sorted(by_rule):
            entries = sorted(by_rule[rule])
            total = sum(n for _, n in entries)
            print(f"\n== {rule}：{len(entries)} 个文件，{total} 处")
            for rel, n in entries:
                print(f"  {n:4d}  {rel}")
        print(f"\n[platform] 合计 {len(current)} 个文件-规则")
        return 0

    allowed = set(load_baseline_keys())
    added = sorted(current - allowed)
    fixed = sorted(allowed - current)
    for key in added:
        print(f"[platform][新增] {key}")
    if fixed:
        print(f"[platform] 已清理 {len(fixed)} 条（可运行 --update-baseline 更新基线）")
    if added:
        print(f"[FAIL] 平台隔离：新增 {len(added)} 处（基线 {len(allowed)}，现状 {len(current)}）")
        return 1
    print(f"[PASS] 平台隔离：{len(current)} 处已知违规，未新增（基线 {len(allowed)}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
