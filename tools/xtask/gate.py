from __future__ import annotations

from typing import Any

from .report import merge_summaries


def evaluate_gate(summaries: list[dict[str, Any]], required: list[str]) -> tuple[int, dict[str, Any]]:
    merged = merge_summaries(summaries)
    by_id = {str(target.get("id")): target for target in merged["targets"]}
    missing = [target_id for target_id in required if target_id not in by_id]
    required_not_passed = [
        target_id
        for target_id in required
        if target_id in by_id
        and by_id[target_id].get("status") not in {"passed", "quarantine_only"}
    ]
    statuses = [str(target.get("status", "failed")) for target in merged["targets"]]

    if any(status == "config_error" for status in statuses):
        code = 2
        status = "config_error"
    elif any(status == "infra_error" for status in statuses):
        code = 3
        status = "infra_error"
    elif any(status == "failed" for status in statuses) or required_not_passed or missing:
        code = 1
        status = "failed"
    elif statuses and all(status == "quarantine_only" for status in statuses):
        code = 4
        status = "quarantine_only"
    else:
        code = 0
        status = "passed"

    merged["status"] = status
    merged["gate"] = {
        "required": required,
        "missing": missing,
        "required_not_passed": required_not_passed,
        "exit_code": code,
    }
    return code, merged
