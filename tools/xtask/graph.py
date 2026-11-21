from __future__ import annotations

import dataclasses
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

from .config import load_toml
from .errors import ConfigError


IGNORED_DIRS = {
    ".git",
    ".agents",
    ".clawbench",
    ".next",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "out",
    "target",
}

CLIENT_TARGET_IDS = ("web:frontend", "mobile:client", "extension:extension", "mcp")


@dataclass(frozen=True)
class TestSpec:
    argv: tuple[str, ...]
    cwd: str
    timeout_s: int
    layer: str = "L1"
    required: bool = True
    report: str | None = None


@dataclass(frozen=True)
class Target:
    id: str
    ecosystem: str
    root: str
    package_name: str
    owned_prefixes: tuple[str, ...]
    dependencies: tuple[str, ...] = ()
    tests: tuple[TestSpec, ...] = ()
    tracked: bool = True
    reasons: tuple[str, ...] = ()


@dataclass
class PackageGraph:
    targets: dict[str, Target]
    reverse: dict[str, set[str]] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)


def _posix(path: str) -> str:
    return path.replace(os.sep, "/").strip("/")


def _relative(root: Path, path: Path) -> str:
    try:
        value = path.relative_to(root).as_posix()
    except ValueError:
        value = Path(os.path.relpath(path, root)).as_posix()
    return value or "."


def _under(path: str, prefix: str) -> bool:
    clean = _posix(path)
    base = _posix(prefix)
    if base in ("", "."):
        return True
    return clean == base or clean.startswith(base + "/")


def _find_cjpm_manifests(root: Path) -> Iterable[Path]:
    for dirpath, dirnames, filenames in os.walk(root):
        current = Path(dirpath)
        if current != root and (current / ".git").exists():
            if "cjpm.toml" in filenames:
                yield current / "cjpm.toml"
            dirnames[:] = []
            continue
        dirnames[:] = sorted(name for name in dirnames if name not in IGNORED_DIRS)
        if "cjpm.toml" in filenames:
            yield current / "cjpm.toml"


def _count_test_files(root: Path, prefixes: tuple[str, ...]) -> int:
    count = 0
    for prefix in prefixes:
        base = root / prefix
        if base.is_file():
            if base.name.endswith("_test.cj"):
                count += 1
            continue
        if not base.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(name for name in dirnames if name not in IGNORED_DIRS)
            count += sum(1 for name in filenames if name.endswith("_test.cj"))
    return count


def _safe_id(target_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", target_id)


def _report_path(root: Path, target_root: Path, target_id: str) -> str:
    report_abs = root / "target" / "test-results" / f"{_safe_id(target_id)}.xml"
    return Path(os.path.relpath(report_abs, target_root)).as_posix()


def _cjpm_tests(
    root: Path,
    target_id: str,
    target_root_rel: str,
    prefixes: tuple[str, ...],
    timeout_s: int,
) -> tuple[TestSpec, ...]:
    if _count_test_files(root, prefixes) == 0:
        return ()
    target_root = root if target_root_rel == "." else root / target_root_rel
    report = _report_path(root, target_root, target_id)
    argv = (
        "cjpm",
        "test",
        "--parallel",
        "nCores",
        "--timeout-each",
        f"{timeout_s}s",
        "--report-path",
        report,
        "--report-format",
        "xml",
    )
    return (TestSpec(argv=argv, cwd=target_root_rel, timeout_s=timeout_s, report=report),)


def _node_target(root: Path, target_id: str, rel: str) -> Target | None:
    manifest = root / rel / "package.json"
    if not manifest.exists():
        return None
    try:
        payload = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ConfigError(f"invalid package.json: {manifest}: {exc}") from exc
    name = str(payload.get("name") or target_id)
    return Target(
        id=target_id,
        ecosystem="npm",
        root=rel,
        package_name=name,
        owned_prefixes=(rel,),
    )


def _cargo_target(root: Path, target_id: str, rel: str) -> Target | None:
    manifest = root / rel / "Cargo.toml"
    if not manifest.exists():
        return None
    payload = load_toml(manifest)
    package = payload.get("package", {})
    name = str(package.get("name") or target_id)
    return Target(
        id=target_id,
        ecosystem="cargo",
        root=rel,
        package_name=name,
        owned_prefixes=(rel,),
    )


def build_graph(
    root: Path, *, timeout_s: int = 600, strict: bool = False
) -> PackageGraph:
    root = root.resolve()
    targets: dict[str, Target] = {}
    raw_dependencies: dict[str, list[str]] = {}
    roots: dict[Path, str] = {}
    warnings: list[str] = []

    for manifest in _find_cjpm_manifests(root):
        rel = _relative(root, manifest.parent)
        payload = load_toml(manifest)
        package = payload.get("package", {})
        name = str(package.get("name") or rel)
        target_id = name
        if target_id in targets:
            warnings.append(
                f"duplicate target id {target_id!r} at {rel}; keeping existing target"
            )
            continue
        prefixes = ("src", "cjpm.toml", "cjpm.lock") if rel == "." else (rel,)
        dependencies: list[str] = []
        for section in ("dependencies", "test-dependencies"):
            values = payload.get(section, {})
            if not isinstance(values, dict):
                continue
            for dependency in values.values():
                if isinstance(dependency, dict) and isinstance(dependency.get("path"), str):
                    dependencies.append(dependency["path"])
        target = Target(
            id=target_id,
            ecosystem="cjpm",
            root=rel,
            package_name=name,
            owned_prefixes=prefixes,
            tests=_cjpm_tests(root, target_id, rel, prefixes, timeout_s),
        )
        targets[target_id] = target
        roots[manifest.parent.resolve()] = target_id
        raw_dependencies[target_id] = dependencies

    for target_id, rel in (
        ("web:frontend", "frontend"),
        ("mobile:client", "client"),
        ("extension:extension", "apps/extension"),
    ):
        target = _node_target(root, target_id, rel)
        if target:
            targets[target_id] = target

    cargo = _cargo_target(root, "mcp", "apps/mcp")
    if cargo:
        targets["mcp"] = cargo

    xtask_root = root / "tools" / "xtask"
    if xtask_root.exists():
        targets["xtask"] = Target(
            id="xtask",
            ecosystem="python",
            root="tools/xtask",
            package_name="xtask",
            owned_prefixes=("tools/xtask",),
            tests=(
                TestSpec(
                    argv=(
                        sys.executable,
                        "-m",
                        "unittest",
                        "discover",
                        "-s",
                        "tools/xtask/tests",
                        "-t",
                        ".",
                    ),
                    cwd=".",
                    timeout_s=120,
                ),
            ),
        )

    resolved_dependencies: dict[str, tuple[str, ...]] = {}
    for target_id, raw_paths in raw_dependencies.items():
        target = targets[target_id]
        target_root = root if target.root == "." else root / target.root
        resolved: list[str] = []
        for raw_path in raw_paths:
            dependency_root = (target_root / raw_path).resolve()
            if not dependency_root.exists():
                if strict:
                    raise ConfigError(
                        f"path dependency missing: {target_id} -> {raw_path} ({dependency_root})"
                    )
                warnings.append(f"missing_path_dep: {target_id} -> {raw_path}")
                continue
            dependency_id = roots.get(dependency_root)
            if dependency_id is None:
                warnings.append(
                    f"path dependency has no cjpm.toml: {target_id} -> {raw_path}"
                )
                continue
            if dependency_id != target_id:
                resolved.append(dependency_id)
        resolved_dependencies[target_id] = tuple(dict.fromkeys(resolved))

    final_targets: dict[str, Target] = {}
    for target_id, target in targets.items():
        final_targets[target_id] = dataclasses.replace(
            target, dependencies=resolved_dependencies.get(target_id, ())
        )

    reverse: dict[str, set[str]] = {target_id: set() for target_id in final_targets}
    for target_id, target in final_targets.items():
        for dependency in target.dependencies:
            reverse.setdefault(dependency, set()).add(target_id)

    return PackageGraph(targets=final_targets, reverse=reverse, warnings=warnings)
