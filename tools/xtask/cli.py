from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

from .affected import affected, build_plan, collect_changed, git_head
from .context import find_root
from .doctor import run_doctor
from .errors import ConfigError, XtaskError
from .gate import evaluate_gate
from .graph import build_graph
from .report import read_summary, summary_exit_code, write_json_atomic
from .runner import execute_plan


def _json(value: object) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python3 -m tools.xtask")
    parser.add_argument("--root", type=Path, default=None)
    parser.add_argument("--version", action="version", version="xtask 0.1.0")
    subparsers = parser.add_subparsers(dest="command", required=True)

    doctor = subparsers.add_parser("doctor")
    doctor.add_argument("--strict", action="store_true")
    doctor.add_argument("--json", action="store_true")

    affected_parser = subparsers.add_parser("affected")
    affected_parser.add_argument("--base", default="HEAD")
    affected_parser.add_argument("--include-worktree", dest="include_worktree", action="store_true", default=True)
    affected_parser.add_argument("--no-include-worktree", dest="include_worktree", action="store_false")
    affected_parser.add_argument("--json", action="store_true")

    test = subparsers.add_parser("test")
    test.add_argument("--changed", action="store_true")
    test.add_argument("--base", default="HEAD")
    test.add_argument("--package", action="append", default=[])
    test.add_argument("--dry-run", action="store_true")
    test.add_argument("--timeout-each", default=None)
    test.add_argument("--summary-out", type=Path, default=Path("target/test-results/summary.json"))
    test.add_argument("--json", action="store_true")

    gate = subparsers.add_parser("gate-result")
    gate.add_argument("--summary", action="append", required=True)
    gate.add_argument("--require", action="append", default=[])
    gate.add_argument("--json", action="store_true")
    return parser


def _summary_paths(values: list[str], root: Path) -> list[Path]:
    paths: list[Path] = []
    for value in values:
        path = Path(value)
        if not path.is_absolute():
            path = root / path
        if path.is_dir():
            paths.extend(sorted(path.rglob("summary.json")))
        elif path.exists():
            paths.append(path)
        else:
            raise ConfigError(f"summary path not found: {path}")
    if not paths:
        raise ConfigError("no summary.json found")
    return list(dict.fromkeys(paths))


def _run(args: argparse.Namespace, root: Path) -> int:
    if args.command == "doctor":
        code, payload = run_doctor(root, strict=args.strict)
        if args.json:
            _json(payload)
        else:
            print(f"doctor: {payload['status']}")
            for warning in payload["warnings"]:
                print(f"WARN  {warning}")
            for error in payload["errors"]:
                print(f"ERROR {error}")
        return code

    if args.command == "affected":
        graph = build_graph(root)
        changed = collect_changed(root, args.base, args.include_worktree)
        selected = affected(graph, changed)
        plan = build_plan(graph, selected, changed=changed, base=args.base, head=git_head(root))
        if args.json:
            _json(plan)
        else:
            for target in plan["targets"]:
                print(f"{target['id']}\t{target['ecosystem']}\t{target['status']}")
        return 0

    if args.command == "test":
        graph = build_graph(root)
        changed = collect_changed(root, args.base, True) if args.changed else []
        selected = affected(graph, changed) if changed else []
        if args.package:
            missing = sorted(set(args.package) - set(graph.targets))
            if missing:
                raise ConfigError(f"unknown package target(s): {', '.join(missing)}")
            allowed = set(args.package)
            if args.changed:
                selected = [target for target in selected if target.id in allowed]
            else:
                selected = [graph.targets[name] for name in sorted(allowed)]
        plan = build_plan(graph, selected, changed=changed, base=args.base, head=git_head(root))
        if args.dry_run:
            _json(plan)
            return 0
        summary = execute_plan(root, plan, timeout_override=args.timeout_each)
        write_json_atomic(root / args.summary_out, summary)
        if args.json:
            _json(summary)
        else:
            print(f"test: {summary['status']} ({summary['duration_ms']} ms)")
            for target in summary["targets"]:
                print(f"{target['id']}\t{target['status']}\t{target['passed']}/{target['total']}")
        return summary_exit_code(summary)

    if args.command == "gate-result":
        paths = _summary_paths(args.summary, root)
        summaries = [read_summary(path) for path in paths]
        code, merged = evaluate_gate(summaries, args.require)
        if args.json:
            _json(merged)
        else:
            print(f"gate: {merged['status']}")
            for item in merged.get("gate", {}).get("missing", []):
                print(f"MISSING {item}")
        return code

    raise ConfigError(f"unsupported command: {args.command}")


def main(argv: Sequence[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        root = args.root.resolve() if args.root else find_root()
        return _run(args, root)
    except XtaskError as exc:
        print(f"xtask: {exc}", file=sys.stderr)
        return exc.exit_code
