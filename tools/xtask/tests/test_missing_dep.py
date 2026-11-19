from __future__ import annotations

import contextlib
import io
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.xtask.affected import affected
from tools.xtask.cli import main
from tools.xtask.doctor import run_doctor
from tools.xtask.errors import ConfigError
from tools.xtask.graph import build_graph


WARNING = "missing_path_dep: lanlu_client_next -> ../packages/cangjie-gui"


class MissingPathDependencyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self._write(
            "client-next/cjpm.toml",
            '[package]\nname = "lanlu_client_next"\n\n'
            '[dependencies]\ncui = { path = "../packages/cangjie-gui" }\n',
        )
        self._write("client-next/src/client_test.cj", "@Test\nfunc testClient() {}\n")
        self._write("tools/xtask/cli.py", "# xtask target marker\n")
        self._git("init", "-q")
        self._git("add", "-A")
        self._git(
            "-c",
            "user.name=xtask-test",
            "-c",
            "user.email=xtask@example.invalid",
            "commit",
            "-qm",
            "fixture",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write(self, relative: str, content: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _git(self, *args: str) -> None:
        result = subprocess.run(
            ["git", *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stderr)

    def test_01_default_graph_warns_and_skips_edge(self) -> None:
        graph = build_graph(self.root)
        self.assertIn(WARNING, graph.warnings)
        self.assertEqual((), graph.targets["lanlu_client_next"].dependencies)

    def test_02_strict_graph_raises(self) -> None:
        with self.assertRaises(ConfigError):
            build_graph(self.root, strict=True)

    def test_03_default_doctor_exits_zero_with_warning(self) -> None:
        code, payload = run_doctor(self.root, strict=False)
        self.assertEqual(0, code)
        self.assertIn(WARNING, payload["warnings"])
        self.assertEqual([], payload["errors"])

    def test_04_strict_doctor_exits_two(self) -> None:
        code, payload = run_doctor(self.root, strict=True)
        self.assertEqual(2, code)
        self.assertIn(WARNING, payload["errors"])
        self.assertEqual([], payload["warnings"])

    def test_05_affected_survives_missing_dependency(self) -> None:
        graph = build_graph(self.root)
        selected = affected(graph, ["client-next/src/client_test.cj"])
        self.assertIn("lanlu_client_next", {target.id for target in selected})

    def test_06_test_package_dry_run_exits_zero(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = main(
                [
                    "--root",
                    str(self.root),
                    "test",
                    "--package",
                    "lanlu_client_next",
                    "--dry-run",
                ]
            )
        self.assertEqual(0, code)
        self.assertIn(WARNING, output.getvalue())


if __name__ == "__main__":
    unittest.main()
