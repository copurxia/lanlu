from __future__ import annotations

import unittest

from tools.xtask.gate import evaluate_gate


def summary(status: str, target_id: str = "lanlu") -> dict:
    return {
        "version": 1,
        "status": status,
        "targets": [{"id": target_id, "status": status}],
        "warnings": [],
        "errors": [],
    }


class GateTests(unittest.TestCase):
    def test_pass(self) -> None:
        code, _ = evaluate_gate([summary("passed")], ["lanlu"])
        self.assertEqual(0, code)

    def test_assertion_failure(self) -> None:
        code, _ = evaluate_gate([summary("failed")], ["lanlu"])
        self.assertEqual(1, code)

    def test_infra_failure(self) -> None:
        code, _ = evaluate_gate([summary("infra_error")], ["lanlu"])
        self.assertEqual(3, code)

    def test_required_missing(self) -> None:
        code, merged = evaluate_gate([summary("passed")], ["lcodec"])
        self.assertEqual(1, code)
        self.assertEqual(["lcodec"], merged["gate"]["missing"])

    def test_quarantine_only(self) -> None:
        code, _ = evaluate_gate([summary("quarantine_only")], ["lanlu"])
        self.assertEqual(4, code)


if __name__ == "__main__":
    unittest.main()
