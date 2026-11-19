from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

from .errors import ConfigError


@dataclass(frozen=True)
class Context:
    root: Path
    json_mode: bool = False


def find_root(start: Path | None = None) -> Path:
    cwd = (start or Path.cwd()).resolve()
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ConfigError(f"not inside a git worktree: {cwd}")
    return Path(result.stdout.strip()).resolve()
