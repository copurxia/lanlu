from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from .config import at_least, exact_any, load_toolchain, parse_version
from .errors import ConfigError
from .graph import IGNORED_DIRS, build_graph


TOOL_COMMANDS = {
    "git": ("git", "--version"),
    "cjc": ("cjc", "--version"),
    "cjpm": ("cjpm", "--version"),
    "cargo": ("cargo", "--version"),
    "node": ("node", "--version"),
    "pnpm": ("pnpm", "--version"),
}


def _tool_version(executable: str, args: tuple[str, ...]) -> str | None:
    if shutil.which(executable) is None:
        return None
    try:
        result = subprocess.run(
            list(args),
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    output = (result.stdout or result.stderr).strip()
    match = parse_version(output)
    return ".".join(str(part) for part in match) if match else output.splitlines()[0] if output else None


def _nested_git_roots(root: Path) -> list[str]:
    found: list[str] = []
    for dirpath, dirnames, _ in os.walk(root):
        current = Path(dirpath)
        if current != root and ".git" in dirnames:
            found.append(current.relative_to(root).as_posix())
            dirnames[:] = []
            continue
        dirnames[:] = sorted(name for name in dirnames if name not in IGNORED_DIRS)
    return found


def _tracked_files(root: Path) -> set[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ConfigError(f"git ls-files failed: {result.stderr.strip()}")
    return {item for item in result.stdout.split("\0") if item}


def run_doctor(root: Path, *, strict: bool) -> tuple[int, dict[str, Any]]:
    warnings: list[str] = []
    errors: list[str] = []
    tools: dict[str, Any] = {}

    if sys.version_info < (3, 11):
        errors.append(f"Python >= 3.11 required, got {sys.version.split()[0]}")
    if shutil.which("git") is None:
        errors.append("git is required")

    root_result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if root_result.returncode != 0 or Path(root_result.stdout.strip()).resolve() != root.resolve():
        errors.append(f"doctor must run at the repository root: {root}")

    versions, toolchain_present = load_toolchain(root)
    if not toolchain_present:
        warnings.append("toolchain/versions.toml is missing; using built-in defaults")

    graph = None
    try:
        graph = build_graph(root)
        warnings.extend(graph.warnings)
    except ConfigError as exc:
        errors.append(str(exc))

    tracked: set[str] = set()
    try:
        tracked = _tracked_files(root)
    except ConfigError as exc:
        warnings.append(str(exc))

    for name, command in TOOL_COMMANDS.items():
        version = _tool_version(command[0], command)
        tools[name] = {"path": shutil.which(command[0]), "version": version}
        if version is None and name != "git":
            warnings.append(f"{name} not found or not runnable")

    cangjie = versions.get("cangjie", {})
    cjc_version = tools.get("cjc", {}).get("version")
    if cjc_version:
        expected = tuple(value for value in (cangjie.get("server"), cangjie.get("desktop")) if value)
        if expected and not exact_any(cjc_version, expected):
            warnings.append(
                f"cjc {cjc_version} does not match any target expectation {expected}"
            )
    cjpm_version = tools.get("cjpm", {}).get("version")
    if cjpm_version:
        expected = tuple(value for value in (cangjie.get("server"), cangjie.get("desktop")) if value)
        if expected and not exact_any(cjpm_version, expected):
            warnings.append(
                f"cjpm {cjpm_version} does not match any target expectation {expected}"
            )

    node_version = tools.get("node", {}).get("version")
    node_min = versions.get("node", {}).get("min")
    if node_version and node_min and not at_least(node_version, node_min):
        warnings.append(f"node {node_version} is below required {node_min}")

    pnpm_version = tools.get("pnpm", {}).get("version")
    pnpm_expected = versions.get("pnpm", {}).get("version")
    if pnpm_version and pnpm_expected and not exact_any(pnpm_version, (pnpm_expected,)):
        warnings.append(f"pnpm {pnpm_version} does not match required {pnpm_expected}")

    for nested in _nested_git_roots(root):
        warnings.append(f"nested git repository: {nested}")

    if graph:
        for target in graph.targets.values():
            if target.root == ".":
                continue
            prefix = target.root + "/"
            if not any(item == target.root or item.startswith(prefix) for item in tracked):
                warnings.append(
                    f"target {target.id} exists at {target.root} but is not tracked by git"
                )

    if strict:
        errors.extend(warnings)
        warnings = []

    status = "error" if errors else "warning" if warnings else "ok"
    payload = {
        "version": 1,
        "status": status,
        "root": str(root),
        "python": sys.version.split()[0],
        "toolchain": versions,
        "toolchain_file": toolchain_present,
        "tools": tools,
        "warnings": warnings,
        "errors": errors,
    }
    return (2 if errors else 0), payload
