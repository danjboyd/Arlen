#!/usr/bin/env python3
"""Behavioral checks for the xctest JUnit summary and DSN-skip gate."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "junit_report.py"

REPORT = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="ArlenUnitTests" tests="4" failures="1" errors="0" skipped="1">
  <testsuite name="PgTests" tests="3" failures="1" errors="0" skipped="1">
    <testcase classname="PgTests" name="testPasses" time="0.01"/>
    <testcase classname="PgTests" name="testFails" time="0.02">
      <failure message="PgTests.m:12: ((1) equal to (2)) failed">PgTests.m:12</failure>
    </testcase>
    <testcase classname="PgTests" name="testNeedsDatabase" time="0.00">
      <skipped message="PgTests.m:40: ([dsn length] &gt; 0) is false: ARLEN_PG_TEST_DSN is not set"/>
    </testcase>
  </testsuite>
  <testsuite name="TimeoutTests" tests="1" failures="0" errors="1" skipped="0">
    <testcase classname="TimeoutTests" name="testHangs" time="300.0">
      <error message="Test exceeded execution time allowance of 300 seconds"/>
    </testcase>
  </testsuite>
</testsuites>
"""


class JUnitReportTests(unittest.TestCase):
    def run_script(self, results_dir, *args, env_extra=None):
        env = {k: v for k, v in os.environ.items() if k not in ("GITHUB_STEP_SUMMARY", "GITHUB_ACTIONS")}
        env.update(env_extra or {})
        return subprocess.run([sys.executable, str(SCRIPT), str(results_dir), *args],
                              capture_output=True, text=True, env=env, check=False)

    def write_report(self, root, name="ArlenUnitTests.xml"):
        path = Path(root) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(REPORT, encoding="utf-8")

    def test_summary_counts_failures_errors_and_skips(self):
        with tempfile.TemporaryDirectory() as root:
            self.write_report(root)
            result = self.run_script(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("1 passed, 2 failed, 1 skipped", result.stdout)
            self.assertIn("`PgTests/testFails`", result.stdout)
            self.assertIn("`TimeoutTests/testHangs`", result.stdout)
            self.assertIn("ARLEN_PG_TEST_DSN is not set", result.stdout)

    def test_skip_gate_fails_only_for_matching_skip_reasons(self):
        with tempfile.TemporaryDirectory() as root:
            self.write_report(root, "postgres/ArlenUnitTests--only-PgTests.xml")
            failing = self.run_script(root, "--fail-on-skip-matching", "ARLEN_PG_TEST_DSN")
            self.assertEqual(failing.returncode, 1)
            self.assertIn("PgTests/testNeedsDatabase", failing.stderr)
            passing = self.run_script(root, "--fail-on-skip-matching", "ARLEN_MSSQL_TEST_DSN")
            self.assertEqual(passing.returncode, 0, passing.stderr)

    def test_github_summary_and_annotations(self):
        with tempfile.TemporaryDirectory() as root:
            self.write_report(root)
            summary = Path(root) / "summary.md"
            result = self.run_script(root, "--title", "lane results",
                                     env_extra={"GITHUB_STEP_SUMMARY": str(summary),
                                                "GITHUB_ACTIONS": "true"})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("### lane results", summary.read_text(encoding="utf-8"))
            self.assertIn("::error title=PgTests/testFails::", result.stdout)
            self.assertNotIn("testNeedsDatabase", result.stdout)

    def test_missing_results_directory_is_reported_not_fatal(self):
        with tempfile.TemporaryDirectory() as root:
            result = self.run_script(Path(root) / "absent")
            self.assertEqual(result.returncode, 0)
            self.assertIn("no JUnit reports", result.stderr)


if __name__ == "__main__":
    unittest.main()
