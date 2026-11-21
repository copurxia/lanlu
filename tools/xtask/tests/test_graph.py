from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.xtask.affected import affected, build_plan
from tools.xtask.graph import build_graph


class GraphAffectedTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self._write(
            "cjpm.toml",
            "[package]\nname = \"lanlu\"\n\n[dependencies]\nlib = { path = \"lib\" }\nleaf = { path = \"lib/leaf\" }\n",
        )
        self._write("src/main_test.cj", "@Test\nfunc testMain() {}\n")
        self._write(
            "lib/cjpm.toml",
            "[package]\nname = \"lib\"\n\n[dependencies]\nleaf = { path = \"leaf\" }\n",
        )
        self._write("lib/src/lib_test.cj", "@Test\nfunc testLib() {}\n")
        self._write("lib/leaf/cjpm.toml", "[package]\nname = \"leaf\"\n")
        self._write("lib/leaf/src/leaf_test.cj", "@Test\nfunc testLeaf() {}\n")
        self._write(
            "apps/desktop/cjpm.toml",
            "[package]\nname = \"lanlu_client_next\"\n\n[dependencies]\nleaf = { path = \"../../lib/leaf\" }\n",
        )
        self._write("apps/desktop/src/client_test.cj", "@Test\nfunc testClient() {}\n")
        self._write("apps/web/package.json", json.dumps({"name": "lanlu-frontend"}))
        self._write("apps/mobile/package.json", json.dumps({"name": "LanluClient"}))
        self._write("apps/extension/package.json", json.dumps({"name": "extension"}))
        self._write("apps/mcp/Cargo.toml", "[package]\nname = \"lanlu-mcp\"\nversion = \"0.1.0\"\n")
        self._write("tools/xtask/cli.py", "# test target\n")
        self.graph = build_graph(self.root)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write(self, relative: str, content: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _ids(self, changed: list[str]) -> set[str]:
        return {target.id for target in affected(self.graph, changed)}

    def test_01_root_change_selects_server(self) -> None:
        self.assertIn("lanlu", self._ids(["src/main.cj"]))

    def test_02_dependency_change_uses_reverse_closure(self) -> None:
        ids = self._ids(["lib/leaf/src/leaf_test.cj"])
        self.assertTrue({"leaf", "lib", "lanlu", "lanlu_client_next"}.issubset(ids))

    def test_03_docs_change_selects_nothing(self) -> None:
        self.assertEqual(set(), self._ids(["docs/testing-roadmap.md"]))

    def test_04_xtask_change_selects_xtask(self) -> None:
        self.assertEqual({"xtask"}, self._ids(["tools/xtask/cli.py"]))

    def test_05_toolchain_change_selects_all_targets(self) -> None:
        ids = self._ids(["toolchain/versions.toml"])
        self.assertTrue({"lanlu", "web:frontend", "mobile:client", "mcp", "xtask"}.issubset(ids))

    def test_06_unknown_change_selects_nothing(self) -> None:
        self.assertEqual(set(), self._ids(["notes.unknown"]))

    def test_07_client_change_does_not_pull_dependencies(self) -> None:
        self.assertEqual({"lanlu_client_next"}, self._ids(["apps/desktop/src/main.cj"]))

    def test_08_plan_shape_and_matrix(self) -> None:
        targets = affected(self.graph, ["toolchain/versions.toml"])
        plan = build_plan(
            self.graph,
            targets,
            changed=["toolchain/versions.toml"],
            base="HEAD~1",
            head="abc1234",
        )
        self.assertEqual(1, plan["version"])
        self.assertIn("lanlu_client_next", plan["matrix"]["cangjie"])
        self.assertIn("mobile:client", plan["matrix"]["clients"])
        self.assertTrue(plan["targets"])


if __name__ == "__main__":
    unittest.main()
