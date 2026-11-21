#!/usr/bin/env python3
"""依赖白名单守卫（计划 §4.5 / §16.2 T0）。

检查每个仓颉包（cjpm.toml）与 Rust 包（Cargo.toml）的：
  1. cjpm.toml [dependencies] 里声明的依赖是否在白名单内；
  2. 源码 import 的顶层包是否在白名单内（含 own / std / stdx）。

违规集合与 tools/quality-baseline.toml 的 [deps] 对比：
  * 违规数 > 基线  -> 失败（新增违规）
  * 违规数 < 基线  -> 提示更新基线（清理完成后执行 --update-baseline）
这样迁移期可以逐条减少违规而不阻塞 CI，又不可能悄悄加回来。

用法：
  python3 tools/check-deps.py
  python3 tools/check-deps.py --report
  python3 tools/check-deps.py --update-baseline
"""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "tools" / "deps-rules.toml"
BASELINE = ROOT / "tools" / "quality-baseline.toml"

SKIP_DIRS = {"target", ".git", "node_modules", ".research-ohos", "build-script-cache", "reports"}

IMPORT_RE = re.compile(r"^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
CJ_ROOTS = {"std", "stdx", "core", "ohos"}


def load_rules() -> dict:
    with RULES.open("rb") as f:
        return tomllib.load(f)


def load_baseline() -> dict:
    if not BASELINE.exists():
        return {}
    with BASELINE.open("rb") as f:
        return tomllib.load(f)


def write_baseline(sections: dict[str, list[str]]) -> None:
    lines = [
        "# 质量基线（计划 §16.2 T0）——由 tools/check-*.py --update-baseline 生成，勿手改。",
        "# 记录迁移起点的问题集合；数量只允许下降。清理后运行对应脚本刷新。",
        "",
    ]
    for name, keys in sections.items():
        lines.append(f"[{name}]")
        if keys:
            lines.append("keys = [")
            for k in sorted(set(keys)):
                lines.append(f'  "{k}",')
            lines.append("]")
        else:
            lines.append("keys = []")
        lines.append("")
    BASELINE.write_text("\n".join(lines), encoding="utf-8")


def cj_deps(toml_path: Path) -> list[str]:
    with toml_path.open("rb") as f:
        data = tomllib.load(f)
    deps = data.get("dependencies", {}) or {}
    names = list(deps.keys())
    for target in (data.get("target", {}) or {}).values():
        if isinstance(target, dict):
            names += list((target.get("dependencies", {}) or {}).keys())
    return sorted(set(names))


def cargo_deps(toml_path: Path) -> list[str]:
    with toml_path.open("rb") as f:
        data = tomllib.load(f)
    names = list((data.get("dependencies", {}) or {}).keys())
    names += list((data.get("dev-dependencies", {}) or {}).keys())
    return sorted(set(n for n in names if n != "wgpu-hal"))  # wgpu-hal 是 [patch] 的 vendored 依赖


def cj_import_roots(src_dir: Path) -> set[str]:
    roots: set[str] = set()
    for path in src_dir.rglob("*.cj"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        # 去掉块注释里被引用的 import 示例
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
        for m in IMPORT_RE.finditer(text):
            roots.add(m.group(1))
    return roots


def collect(rules: dict) -> tuple[dict[str, set[str]], dict[str, dict]]:
    """返回 {包名: 违规键集合}, {包名: 规则}。"""
    global_roots = set((rules.get("global") or {}).get("allowed_import_roots", [])) | CJ_ROOTS
    default = rules.get("default") or {}
    pkg_rules = rules.get("package") or {}
    violations: dict[str, set[str]] = {}
    used_rules: dict[str, dict] = {}
    covered_dirs: set[Path] = set()

    def scan(name: str, pkg_dir: Path, rule: dict) -> set[str]:
        allowed = set(rule.get("allowed_deps", []))
        found: set[str] = set()
        if rule.get("kind", "cangjie") == "cangjie":
            manifest = pkg_dir / "cjpm.toml"
            if manifest.exists():
                for dep in cj_deps(manifest):
                    if dep not in allowed:
                        found.add(f"{name}:dep:{dep}")
            src = pkg_dir / "src"
            if src.is_dir():
                for imp in cj_import_roots(src):
                    if imp in global_roots or imp == name:
                        continue
                    if imp not in allowed:
                        found.add(f"{name}:import:{imp}")
        else:
            manifest = pkg_dir / "Cargo.toml"
            if manifest.exists():
                for dep in cargo_deps(manifest):
                    if dep not in allowed:
                        found.add(f"{name}:dep:{dep}")
        return found

    for name, rule in pkg_rules.items():
        if not isinstance(rule, dict) or "path" not in rule:
            continue
        pkg_dir = ROOT / rule["path"]
        if not pkg_dir.is_dir():
            continue
        used_rules[name] = rule
        covered_dirs.add(pkg_dir.resolve())
        found = scan(name, pkg_dir, rule)
        if found:
            violations[name] = found

    # 未登记规则的仓颉包走 default（默认只允许标准库）。
    # 只看 git 已跟踪的包：未跟踪目录是工作副本/实验快照（如 cangjie-gui-p0），
    # 把它们的依赖算成违规只会制造噪声。
    import subprocess
    try:
        tracked = set(subprocess.run(["git", "ls-files"], cwd=ROOT,
                                     capture_output=True, text=True, check=False).stdout.splitlines())
    except OSError:
        tracked = None
    # packages/ 是可复用库；apps/server 是 PR6 从仓库根迁入的可部署端，由
    # [package.lanlu] 登记（进 covered_dirs 后这里会跳过）。仍显式列出它，是兜底：
    # 万一规则条目被删，服务端会退回 default 规则并**报违规**，而不是静默不扫。
    # apps/desktop 同理由 [package.lanlu_client_next] 登记，无需重复枚举。
    for manifest in sorted(
        list(ROOT.glob("packages/*/cjpm.toml")) + [ROOT / "apps" / "server" / "cjpm.toml"]
    ):
        if tracked is not None and manifest.relative_to(ROOT).as_posix() not in tracked:
            continue
        pkg_dir = manifest.parent
        if pkg_dir.resolve() in covered_dirs:
            continue
        name = pkg_dir.name
        found = scan(name, pkg_dir, default)
        used_rules[name] = default
        if found:
            violations[name] = found

    return violations, used_rules


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="按包列出全部违规（不看基线）")
    ap.add_argument("--update-baseline", action="store_true", help="把当前违规写成新基线")
    args = ap.parse_args()

    rules = load_rules()
    violations, used_rules = collect(rules)
    current = set()
    for keys in violations.values():
        current |= keys

    if args.update_baseline:
        baseline = load_baseline()
        platform = baseline.get("platform", {}).get("keys", [])
        write_baseline({"deps": sorted(current), "platform": platform})
        print(f"[deps] 基线已更新：{len(current)} 条违规")
        return 0

    if args.report:
        for name in sorted(violations):
            keys = sorted(violations[name])
            if not keys:
                continue
            print(f"\n== {name}（{len(keys)}）")
            for k in keys:
                print(f"  {k.split(':', 1)[1]}")
        print(f"\n[deps] 合计 {len(current)} 条违规")
        return 0

    baseline = load_baseline()
    allowed = set(baseline.get("deps", {}).get("keys", []))
    added = sorted(current - allowed)
    fixed = sorted(allowed - current)

    for key in added:
        print(f"[deps][新增] {key}")
    if fixed:
        print(f"[deps] 已清理 {len(fixed)} 条（可运行 --update-baseline 更新基线）")

    if added:
        print(f"[FAIL] 依赖白名单：新增 {len(added)} 条违规（基线 {len(allowed)} 条，现状 {len(current)} 条）")
        return 1

    print(f"[PASS] 依赖白名单：{len(current)} 条已知违规，未新增（基线 {len(allowed)}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
