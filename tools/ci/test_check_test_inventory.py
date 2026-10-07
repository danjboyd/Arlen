#!/usr/bin/env python3
"""Behavioral checks for the xctest test-inventory comparison."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "check_test_inventory.py"

BASELINE = """ArlenUnitTests/FooTests/testA
ArlenUnitTests/FooTests/testB
"""


class TestInventoryTests(unittest.TestCase):
    def run_script(self, root, *args):
        root = Path(root)
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--repo-root", str(root),
             "--listing-dir", str(root / "listing"), *args],
            capture_output=True, text=True, check=False)

    def write(self, root, relative, text):
        path = Path(root) / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def baseline_path(self, root, bundle="ArlenUnitTests"):
        return Path(root) / "tests/fixtures/test_inventory" / f"{bundle}.tests.txt"

    def test_matching_listing_passes_and_ignores_noise_and_order(self):
        with tempfile.TemporaryDirectory() as root:
            self.write(root, "tests/fixtures/test_inventory/ArlenUnitTests.tests.txt", BASELINE)
            self.write(root, "listing/ArlenUnitTests.tests.txt",
                       "2026-10-07 12:00:00 loading bundle\n"
                       "ArlenUnitTests/FooTests/testB\n\nArlenUnitTests/FooTests/testA\n")
            result = self.run_script(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("2 tests across 1 bundle(s)", result.stdout)

    def test_missing_test_fails_and_names_it(self):
        with tempfile.TemporaryDirectory() as root:
            self.write(root, "tests/fixtures/test_inventory/ArlenUnitTests.tests.txt", BASELINE)
            self.write(root, "listing/ArlenUnitTests.tests.txt", "ArlenUnitTests/FooTests/testA\n")
            result = self.run_script(root)
            self.assertEqual(result.returncode, 1)
            self.assertIn("- ArlenUnitTests/FooTests/testB", result.stderr)
            self.assertIn("make update-test-inventory", result.stderr)

    def test_unrecorded_test_fails(self):
        with tempfile.TemporaryDirectory() as root:
            self.write(root, "tests/fixtures/test_inventory/ArlenUnitTests.tests.txt", BASELINE)
            self.write(root, "listing/ArlenUnitTests.tests.txt",
                       BASELINE + "ArlenUnitTests/FooTests/testC\n")
            result = self.run_script(root)
            self.assertEqual(result.returncode, 1)
            self.assertIn("+ ArlenUnitTests/FooTests/testC", result.stderr)

    def test_missing_listing_fails(self):
        with tempfile.TemporaryDirectory() as root:
            self.write(root, "tests/fixtures/test_inventory/ArlenUnitTests.tests.txt", BASELINE)
            result = self.run_script(root)
            self.assertEqual(result.returncode, 1)
            self.assertIn("ArlenUnitTests: no listing", result.stderr)

    def test_update_writes_sorted_baseline_and_drops_stale_bundles(self):
        with tempfile.TemporaryDirectory() as root:
            self.write(root, "tests/fixtures/test_inventory/OldTests.tests.txt", "OldTests/A/testA\n")
            self.write(root, "listing/ArlenUnitTests.tests.txt",
                       "ArlenUnitTests/FooTests/testB\nnoise\nArlenUnitTests/FooTests/testA\n")
            result = self.run_script(root, "--update", "ArlenUnitTests")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.baseline_path(root).read_text(encoding="utf-8"), BASELINE)
            self.assertFalse(self.baseline_path(root, "OldTests").exists())
            self.assertEqual(self.run_script(root).returncode, 0)

    def test_update_refuses_an_empty_listing(self):
        with tempfile.TemporaryDirectory() as root:
            self.write(root, "listing/ArlenUnitTests.tests.txt", "no tests here\n")
            result = self.run_script(root, "--update", "ArlenUnitTests")
            self.assertEqual(result.returncode, 1)
            self.assertFalse(self.baseline_path(root).exists())


if __name__ == "__main__":
    unittest.main()
