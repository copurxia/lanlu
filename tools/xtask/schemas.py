from __future__ import annotations

from enum import IntEnum


class ExitCode(IntEnum):
    PASS = 0
    FAIL = 1
    CONFIG = 2
    INFRA = 3
    QUARANTINE = 4


TARGET_STATUSES = {
    "planned",
    "passed",
    "failed",
    "skipped",
    "not_configured",
    "config_error",
    "infra_error",
    "quarantine_only",
}

SUMMARY_VERSION = 1
PLAN_VERSION = 1
