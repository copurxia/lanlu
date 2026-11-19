from __future__ import annotations

import json
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from .errors import ConfigError


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].lower()


def parse_cjpm_xml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"total": 0, "passed": 0, "failed": 0, "skipped": 0, "failures": []}
    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        raise ConfigError(f"invalid test report XML: {path}: {exc}") from exc
    root = tree.getroot()
    cases = [
        element
        for element in root.iter()
        if _local_name(element.tag) in {"testcase", "test"}
    ]
    if not cases:
        total = int(root.attrib.get("tests", 0) or 0)
        failed = int(root.attrib.get("failures", 0) or 0) + int(
            root.attrib.get("errors", 0) or 0
        )
        skipped = int(root.attrib.get("skipped", 0) or 0)
        return {
            "total": total,
            "passed": max(0, total - failed - skipped),
            "failed": failed,
            "skipped": skipped,
            "failures": [],
        }

    failures: list[dict[str, Any]] = []
    skipped = 0
    for case in cases:
        children = list(case)
        failing_children = [
            child for child in children if _local_name(child.tag) in {"failure", "error"}
        ]
        skip_children = [child for child in children if _local_name(child.tag) == "skipped"]
        result = (case.attrib.get("result") or case.attrib.get("status") or "").lower()
        if skip_children:
            skipped += 1
            continue
        if not failing_children and result not in {"fail", "failed", "error"}:
            continue
        child = failing_children[0] if failing_children else None
        message = ""
        if child is not None:
            message = child.attrib.get("message") or (child.text or "").strip()
        failures.append(
            {
                "test_id": case.attrib.get("name")
                or case.attrib.get("classname")
                or "unknown",
                "kind": "assertion",
                "message": message or "test failed",
                "file": case.attrib.get("file") or case.attrib.get("classname"),
                "line": int(case.attrib["line"]) if case.attrib.get("line", "").isdigit() else None,
            }
        )

    total = len(cases)
    failed = len(failures)
    return {
        "total": total,
        "passed": max(0, total - failed - skipped),
        "failed": failed,
        "skipped": skipped,
        "failures": failures,
    }


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
        temporary = Path(handle.name)
    temporary.replace(path)


def read_summary(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ConfigError(f"summary not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ConfigError(f"invalid summary JSON: {path}: {exc}") from exc
    if not isinstance(payload, dict) or not isinstance(payload.get("targets"), list):
        raise ConfigError(f"invalid summary shape: {path}")
    return payload


def merge_summaries(summaries: list[dict[str, Any]]) -> dict[str, Any]:
    targets: list[dict[str, Any]] = []
    warnings: list[str] = []
    errors: list[str] = []
    seen: set[str] = set()
    for summary in summaries:
        for target in summary.get("targets", []):
            target_id = str(target.get("id", ""))
            if target_id and target_id in seen:
                continue
            if target_id:
                seen.add(target_id)
            targets.append(target)
        warnings.extend(str(item) for item in summary.get("warnings", []))
        errors.extend(str(item) for item in summary.get("errors", []))
    return {
        "version": 1,
        "status": "unknown",
        "targets": targets,
        "warnings": list(dict.fromkeys(warnings)),
        "errors": list(dict.fromkeys(errors)),
    }


def summary_exit_code(summary: dict[str, Any]) -> int:
    statuses = [str(target.get("status", "failed")) for target in summary.get("targets", [])]
    if any(status == "config_error" for status in statuses):
        return 2
    if any(status == "infra_error" for status in statuses):
        return 3
    if any(status == "failed" for status in statuses):
        return 1
    if statuses and all(status == "quarantine_only" for status in statuses):
        return 4
    return 0
