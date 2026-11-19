from __future__ import annotations

import dataclasses
import subprocess
from collections import deque
from pathlib import Path

from .errors import ConfigError
from .graph import CLIENT_TARGET_IDS, PackageGraph, Target, _under


CONFIG_PREFIXES = ("toolchain/", ".github/", ".gitea/")


def _git(root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ConfigError(
            f"git {' '.join(args)} failed: {result.stderr.strip() or result.stdout.strip()}"
        )
    return result.stdout


def git_head(root: Path) -> str:
    return _git(root, "rev-parse", "--short", "HEAD").strip()


def collect_changed(root: Path, base: str | None, include_worktree: bool) -> list[str]:
    base_ref = base or "HEAD"
    if include_worktree:
        output = _git(root, "diff", "--name-only", base_ref)
        untracked = _git(root, "ls-files", "--others", "--exclude-standard")
        paths = output.splitlines() + untracked.splitlines()
    else:
        range_spec = f"{base_ref}...HEAD"
        paths = _git(root, "diff", "--name-only", range_spec).splitlines()
    normalized = [path.strip().replace("\\", "/") for path in paths if path.strip()]
    return list(dict.fromkeys(normalized))


def affected(graph: PackageGraph, changed: list[str]) -> list[Target]:
    direct: dict[str, set[str]] = {}
    all_ids = set(graph.targets)

    for path in changed:
        clean = path.replace("\\", "/")
        while clean.startswith("./"):
            clean = clean[2:]
        if clean.startswith("docs/") or clean.endswith(".md"):
            continue
        if clean.startswith("tools/xtask/"):
            direct.setdefault("xtask", set()).add(path)
            continue
        if clean == "justfile" or clean == ".cnb.yml" or any(
            clean.startswith(prefix) for prefix in CONFIG_PREFIXES
        ):
            for target_id in all_ids:
                direct.setdefault(target_id, set()).add(path)
            continue

        matches: list[Target] = []
        for target in graph.targets.values():
            for prefix in target.owned_prefixes:
                if _under(clean, prefix):
                    matches.append(target)
                    break
        if matches:
            selected = max(matches, key=lambda item: max(len(prefix) for prefix in item.owned_prefixes))
            direct.setdefault(selected.id, set()).add(path)

    reasons: dict[str, set[str]] = {target_id: set(paths) for target_id, paths in direct.items()}
    queue = deque(direct)
    seen = set(direct)
    while queue:
        dependency = queue.popleft()
        for dependent in sorted(graph.reverse.get(dependency, ())):
            reasons.setdefault(dependent, set()).add(f"dependency:{dependency} changed")
            if dependent not in seen:
                seen.add(dependent)
                queue.append(dependent)

    result: list[Target] = []
    for target_id in sorted(reasons):
        target = graph.targets.get(target_id)
        if target is None:
            continue
        result.append(dataclasses.replace(target, reasons=tuple(sorted(reasons[target_id]))))
    return result


def build_plan(
    graph: PackageGraph,
    targets: list[Target],
    *,
    changed: list[str],
    base: str | None,
    head: str,
) -> dict:
    target_payloads = []
    for target in targets:
        status = "planned" if target.tests else "not_configured"
        target_payloads.append(
            {
                "id": target.id,
                "ecosystem": target.ecosystem,
                "root": target.root,
                "package_name": target.package_name,
                "reasons": list(target.reasons),
                "status": status,
                "tests": [
                    {
                        "argv": list(spec.argv),
                        "cwd": spec.cwd,
                        "timeout_s": spec.timeout_s,
                        "layer": spec.layer,
                        "required": spec.required,
                        "report": spec.report,
                    }
                    for spec in target.tests
                ],
            }
        )

    return {
        "version": 1,
        "base": base or "HEAD",
        "head": head,
        "changed_files": changed,
        "targets": target_payloads,
        "matrix": {
            "cangjie": sorted(
                target.id for target in targets if target.ecosystem == "cjpm"
            ),
            "clients": sorted(
                target.id for target in targets if target.id in CLIENT_TARGET_IDS
            ),
        },
        "warnings": list(graph.warnings),
        "errors": [],
    }


def build_github_matrix(plan: dict) -> dict[str, list[dict[str, str]]]:
    cangjie: list[dict[str, str]] = []
    clients: list[dict[str, str]] = []
    for target in plan["targets"]:
        if target["ecosystem"] == "cjpm":
            cangjie.append(
                {
                    "pkg": target["id"],
                    "root": target["root"],
                    "status": target["status"],
                }
            )
        if target["id"] in CLIENT_TARGET_IDS:
            clients.append(
                {
                    "target": target["id"],
                    "root": target["root"],
                    "status": target["status"],
                }
            )
    cangjie.sort(key=lambda item: item["pkg"])
    clients.sort(key=lambda item: item["target"])
    return {"cangjie": cangjie, "clients": clients}
