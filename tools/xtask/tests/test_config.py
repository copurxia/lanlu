from __future__ import annotations

import unittest

from tools.xtask.config import at_least, exact_any, parse_version


class VersionTests(unittest.TestCase):
    def test_short_versions_are_normalized_to_three_parts(self) -> None:
        self.assertEqual((20, 0, 0), parse_version("20"))
        self.assertEqual((24, 1, 0), parse_version("24.1"))

    def test_tool_output_prefixes_and_suffixes_are_ignored(self) -> None:
        self.assertEqual((24, 22, 3), parse_version("v24.22.3"))
        self.assertEqual((1, 2, 0), parse_version("Cangjie 1.2.0 (std)"))

    def test_minimum_comparison_accepts_short_config(self) -> None:
        self.assertTrue(at_least("24.22.3", "20"))
        self.assertFalse(at_least("19.9.0", "20"))

    def test_exact_comparison_accepts_short_config(self) -> None:
        self.assertTrue(exact_any("20.0.0", ("20",)))
        self.assertFalse(exact_any("20.1.0", ("20",)))


if __name__ == "__main__":
    unittest.main()
