from __future__ import annotations


class XtaskError(Exception):
    """Base class for expected xtask failures."""

    exit_code = 2

    def __init__(self, message: str, *, exit_code: int | None = None) -> None:
        super().__init__(message)
        if exit_code is not None:
            self.exit_code = exit_code


class ConfigError(XtaskError):
    exit_code = 2


class InfraError(XtaskError):
    exit_code = 3
