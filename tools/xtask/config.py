from __future__ import annotations

import re
import tomllib
from pathlib import Path
from typing import Any

from .errors import ConfigError


DEFAULT_TOOLCHAIN: dict[str, dict[str, str]] = {
    "cangjie": {"server": "1.2.0", "desktop": "1.1.3"},
    "node": {"min": "22.11.0"},
    "pnpm": {"version": "10.33.0"},
    "python": {"min": "3.11"},
}

VERSION_RE = re.compile(
    r"[vV]?\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-+_.].*)?"
)


def load_toml(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError as exc:
        raise ConfigError(f"manifest not found: {path}") from exc
    except tomllib.TOMLDecodeError as exc:
        raise ConfigError(f"invalid TOML: {path}: {exc}") from exc


def load_toolchain(root: Path) -> tuple[dict[str, dict[str, str]], bool]:
    path = root / "toolchain" / "versions.toml"
    data: dict[str, dict[str, str]] = {
        section: dict(values) for section, values in DEFAULT_TOOLCHAIN.items()
    }
    if not path.exists():
        return data, False
    parsed = load_toml(path)
    for section, values in parsed.items():
        if not isinstance(values, dict):
            continue
        target = data.setdefault(section, {})
        for key, value in values.items():
            if isinstance(value, str):
                target[str(key)] = value
    return data, True


def parse_version(text: str) -> tuple[int, int, int] | None:
    match = VERSION_RE.search(text)
    if not match:
        return None
    major, minor, patch = match.groups()
    return (int(major), int(minor or 0), int(patch or 0))


def at_least(actual: str, expected: str) -> bool:
    actual_tuple = parse_version(actual)
    expected_tuple = parse_version(expected)
    return bool(actual_tuple and expected_tuple and actual_tuple >= expected_tuple)


def exact_any(actual: str, expected: tuple[str, ...]) -> bool:
    actual_tuple = parse_version(actual)
    if actual_tuple is None:
        return False
    return any(actual_tuple == parse_version(item) for item in expected)
