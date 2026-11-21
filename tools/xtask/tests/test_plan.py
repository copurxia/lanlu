from __future__ import annotations

import contextlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.xtask.cli import main


class GitHubMatrixPlanTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self._write(
            "cjpm.toml",
            '[package]\nname = "lanlu"\n\n'
            '[dependencies]\nlbase = { path = "packages/lbase" }\n',
        )
        self._write("src/main_test.cj", "@Test\nfunc testMain() {}\n")
        self._write(
            "packages/lbase/cjpm.toml", '[package]\nname = "lbase"\n'
        )
        self._write("packages/lbase/src/lib.cj", "package lbase\n")
        self._write("packages/lbase/src/lib_test.cj", "@Test\nfunc testLib() {}\n")
        self._write(
            "packages/lcodec/cjpm.toml",
            '[package]\nname = "lcodec"\n\n'
            '[dependencies]\nlbase = { path = "../lbase" }\n',
        )
        self._write("packages/lcodec/src/codec_test.cj", "@Test\nfunc testCodec() {}\n")
        self._write(
            "packages/lwindow/cjpm.toml",
            '[package]\nname = "lwindow"\n\n'
            '[dependencies]\nlcodec = { path = "../lcodec" }\n',
        )
        self._write("packages/lwindow/src/window_test.cj", "@Test\nfunc testWindow() {}\n")
        self._write(
            "packages/portcheck/cjpm.toml",
            '[package]\nname = "portcheck"\n\n'
            '[dependencies]\ncui = { path = "../cangjie-gui" }\n',
        )
        self._write(
            "client-next/cjpm.toml",
            '[package]\nname = "lanlu_client_next"\n\n'
            '[dependencies]\nlwindow = { path = "../packages/lwindow" }\n',
        )
        self._write("client-next/src/client_test.cj", "@Test\nfunc testClient() {}\n")
        self._write("frontend/package.json", json.dumps({"name": "lanlu-frontend"}))
        self._write("client/package.json", json.dumps({"name": "LanluClient"}))
        self._write("apps/extension/package.json", json.dumps({"name": "extension"}))
        self._write("apps/mcp/Cargo.toml", '[package]\nname = "lanlu-mcp"\nversion = "0.1.0"\n')
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

    def _plan(self, *extra: str) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main(
                [
                    "--root",
                    str(self.root),
                    "plan",
                    "--github-matrix",
                    *extra,
                ]
            )
        return code, stdout.getvalue(), stderr.getvalue()

    def _matrix(self, *extra: str) -> tuple[dict, str]:
        code, stdout, stderr = self._plan(*extra)
        self.assertEqual(0, code)
        return json.loads(stdout), stderr

    def test_01_docs_change_yields_empty_arrays(self) -> None:
        self._write("docs/testing.md", "# notes\n")
        matrix, _ = self._matrix("--base", "HEAD")
        self.assertEqual([], matrix["cangjie"])
        self.assertEqual([], matrix["clients"])

    def test_02_lbase_change_uses_downstream_closure(self) -> None:
        path = self.root / "packages/lbase/src/lib.cj"
        path.write_text("package lbase\n// changed\n", encoding="utf-8")
        matrix, _ = self._matrix("--base", "HEAD")
        packages = {item["pkg"] for item in matrix["cangjie"]}
        self.assertTrue(
            {"lanlu", "lbase", "lcodec", "lwindow", "lanlu_client_next"}.issubset(packages)
        )
        self.assertNotIn("portcheck", packages)

    def test_03_toolchain_change_yields_full_matrix(self) -> None:
        self._write("toolchain/versions.toml", "[cangjie]\nserver = \"1.2.0\"\n")
        matrix, _ = self._matrix("--base", "HEAD")
        packages = {item["pkg"] for item in matrix["cangjie"]}
        self.assertEqual(
            {"lanlu", "lbase", "lcodec", "lwindow", "portcheck", "lanlu_client_next"},
            packages,
        )

    def test_04_clients_include_all_targets_with_status(self) -> None:
        self._write("toolchain/versions.toml", "[cangjie]\nserver = \"1.2.0\"\n")
        matrix, _ = self._matrix("--base", "HEAD")
        clients = {item["target"]: item for item in matrix["clients"]}
        self.assertEqual(
            {"web:frontend", "mobile:client", "extension:extension", "mcp"},
            set(clients),
        )
        for item in clients.values():
            self.assertEqual({"target", "root", "status"}, set(item))
            self.assertEqual("not_configured", item["status"])
        self.assertEqual({"pkg", "root", "status"}, set(matrix["cangjie"][0]))

    def test_05_stdout_is_json_and_warnings_go_to_stderr(self) -> None:
        code, stdout, stderr = self._plan("--base", "HEAD")
        self.assertEqual(0, code)
        json.loads(stdout)
        self.assertNotIn("WARN", stdout)
        self.assertNotIn("missing_path_dep", stdout)
        self.assertIn(
            "missing_path_dep: portcheck -> ../cangjie-gui", stderr
        )

    def test_06_base_is_required(self) -> None:
        stderr = io.StringIO()
        with self.assertRaises(SystemExit) as raised:
            with contextlib.redirect_stderr(stderr):
                main(["--root", str(self.root), "plan", "--github-matrix"])
        self.assertEqual(2, raised.exception.code)
        self.assertIn("--base", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
