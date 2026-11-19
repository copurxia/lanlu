from __future__ import annotations

import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .graph import _safe_id
from .report import parse_cjpm_xml, summary_exit_code, write_json_atomic


def parse_duration(value: str | None, default: int) -> int:
    if not value:
        return default
    match = re.fullmatch(r"\s*(\d+)\s*([smh]?)\s*", value)
    if not match:
        return default
    amount = int(match.group(1))
    unit = match.group(2)
    return amount * {"": 1, "s": 1, "m": 60, "h": 3600}[unit]


def _target_status(records: list[dict[str, Any]]) -> str:
    statuses = {record["status"] for record in records}
    for candidate in ("config_error", "infra_error", "failed", "quarantine_only"):
        if candidate in statuses:
            return candidate
    if "passed" in statuses:
        return "passed"
    return "not_configured"


def execute_plan(
    root: Path,
    plan: dict[str, Any],
    *,
    timeout_override: str | None = None,
) -> dict[str, Any]:
    started = time.monotonic()
    out_dir = root / "target" / "test-results"
    log_dir = out_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    target_results: list[dict[str, Any]] = []

    for target in plan.get("targets", []):
        tests = target.get("tests", [])
        if not tests:
            target_results.append(
                {
                    "id": target["id"],
                    "ecosystem": target["ecosystem"],
                    "status": "not_configured",
                    "exit_code": 0,
                    "duration_ms": 0,
                    "total": 0,
                    "passed": 0,
                    "failed": 0,
                    "skipped": 0,
                    "flaky": 0,
                    "quarantined": 0,
                    "report": None,
                    "failures": [],
                }
            )
            continue

        records: list[dict[str, Any]] = []
        for index, spec in enumerate(tests):
            argv = [str(part) for part in spec["argv"]]
            cwd = (root / spec["cwd"]).resolve()
            timeout_s = parse_duration(timeout_override, int(spec.get("timeout_s", 600)))
            report = spec.get("report")
            record: dict[str, Any] = {
                "id": target["id"],
                "ecosystem": target["ecosystem"],
                "status": "passed",
                "exit_code": 0,
                "duration_ms": 0,
                "total": 0,
                "passed": 0,
                "failed": 0,
                "skipped": 0,
                "flaky": 0,
                "quarantined": 0,
                "report": report,
                "failures": [],
            }
            if not cwd.exists():
                record.update(status="config_error", exit_code=2)
                record["failures"].append(
                    {
                        "test_id": target["id"],
                        "kind": "config",
                        "message": f"working directory missing: {cwd}",
                        "file": spec.get("cwd"),
                        "line": None,
                    }
                )
                records.append(record)
                continue

            target_started = time.monotonic()
            try:
                result = subprocess.run(
                    argv,
                    cwd=cwd,
                    capture_output=True,
                    text=True,
                    timeout=timeout_s,
                    check=False,
                )
            except FileNotFoundError as exc:
                record.update(status="config_error", exit_code=2)
                record["failures"].append(
                    {
                        "test_id": target["id"],
                        "kind": "config",
                        "message": f"command not found: {exc.filename}",
                        "file": spec.get("cwd"),
                        "line": None,
                    }
                )
                records.append(record)
                continue
            except subprocess.TimeoutExpired:
                record.update(status="infra_error", exit_code=3)
                record["failures"].append(
                    {
                        "test_id": target["id"],
                        "kind": "timeout",
                        "message": f"command timed out after {timeout_s}s",
                        "file": spec.get("cwd"),
                        "line": None,
                    }
                )
                records.append(record)
                continue

            record["duration_ms"] = int((time.monotonic() - target_started) * 1000)
            log_path = log_dir / f"{_safe_id(target['id'])}-{index}.log"
            log_path.write_text(
                f"$ {' '.join(argv)}\n\nSTDOUT\n{result.stdout}\nSTDERR\n{result.stderr}\n",
                encoding="utf-8",
            )

            if report:
                parsed = parse_cjpm_xml((root / report).resolve())
                record.update(
                    total=parsed["total"],
                    passed=parsed["passed"],
                    failed=parsed["failed"],
                    skipped=parsed["skipped"],
                    failures=parsed["failures"],
                )

            if result.returncode == 0 and not record["failures"]:
                record["status"] = "passed"
                record["exit_code"] = 0
            else:
                record["status"] = "failed"
                record["exit_code"] = 1
                if not record["failures"]:
                    record["failures"].append(
                        {
                            "test_id": target["id"],
                            "kind": "process",
                            "message": f"command exited {result.returncode}",
                            "file": spec.get("cwd"),
                            "line": None,
                        }
                    )
            records.append(record)

        target_results.append(
            {
                "id": target["id"],
                "ecosystem": target["ecosystem"],
                "status": _target_status(records),
                "exit_code": max((record["exit_code"] for record in records), default=0),
                "duration_ms": sum(record["duration_ms"] for record in records),
                "total": sum(record["total"] for record in records),
                "passed": sum(record["passed"] for record in records),
                "failed": sum(record["failed"] for record in records),
                "skipped": sum(record["skipped"] for record in records),
                "flaky": 0,
                "quarantined": 0,
                "report": records[0]["report"] if records else None,
                "failures": [failure for record in records for failure in record["failures"]],
            }
        )

    summary = {
        "version": 1,
        "run_id": datetime.now(timezone.utc).strftime("xtask-%Y%m%dT%H%M%SZ"),
        "base": plan.get("base"),
        "head": plan.get("head"),
        "status": "unknown",
        "duration_ms": int((time.monotonic() - started) * 1000),
        "targets": target_results,
        "warnings": list(plan.get("warnings", [])),
        "errors": [],
    }
    code = summary_exit_code(summary)
    summary["status"] = {
        0: "passed",
        1: "failed",
        2: "config_error",
        3: "infra_error",
        4: "quarantine_only",
    }[code]
    write_json_atomic(out_dir / "summary.json", summary)
    return summary
