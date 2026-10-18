#!/usr/bin/env python3
"""Behavioral checks for the scan-build baseline gate."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "static_scan_build_gate.py"

REPORT = """<!-- BUGTYPE {bugtype} -->
<!-- BUGFILE {root}/src/Example.m -->
<!-- FUNCTIONNAME exampleFunction -->
<!-- ISSUEHASHCONTENTOFLINEINCONTEXT {hash} -->
<!-- BUGCATEGORY Unused code -->
<!-- BUGDESC Value stored to 'x' is never read -->
<!-- BUGLINE 12 -->
"""


class StaticScanBuildGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "repo"
        self.reports = Path(self.tmp.name) / "reports" / "2026-01-01-000000-1-1"
        self.baseline = Path(self.tmp.name) / "baseline.json"
        self.root.mkdir()
        self.reports.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def add_report(self, name, bugtype="Dead assignment", issue_hash="abc123"):
        (self.reports / name).write_text(
            REPORT.format(bugtype=bugtype, root=self.root, hash=issue_hash), encoding="utf-8")

    def run_gate(self, *extra):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--reports", str(self.reports.parent),
             "--root", str(self.root), "--baseline", str(self.baseline), *extra],
            capture_output=True, text=True, check=False)

    def test_written_baseline_accepts_current_reports_and_rejects_new_ones(self):
        self.add_report("report-1.html")
        written = self.run_gate("--write-baseline")
        self.assertEqual(written.returncode, 0, written.stderr)
        entry = json.loads(self.baseline.read_text(encoding="utf-8"))["accepted"][0]
        self.assertEqual(entry["file"], "src/Example.m")
        self.assertEqual(entry["reason"], "TODO")

        clean = self.run_gate()
        self.assertEqual(clean.returncode, 0, clean.stdout)

        self.add_report("report-2.html", bugtype="Dereference of null pointer", issue_hash="def456")
        dirty = self.run_gate()
        self.assertEqual(dirty.returncode, 1, dirty.stdout)
        self.assertIn("NEW src/Example.m:12 [Dereference of null pointer]", dirty.stdout)

    def test_stale_entries_do_not_fail_and_rewrite_keeps_reasons(self):
        self.add_report("report-1.html")
        self.run_gate("--write-baseline")
        payload = json.loads(self.baseline.read_text(encoding="utf-8"))
        payload["accepted"][0]["reason"] = "benign dead store"
        self.baseline.write_text(json.dumps(payload), encoding="utf-8")

        self.add_report("report-2.html", issue_hash="def456")
        self.run_gate("--write-baseline")
        reasons = sorted(e["reason"] for e in
                         json.loads(self.baseline.read_text(encoding="utf-8"))["accepted"])
        self.assertEqual(reasons, ["TODO", "benign dead store"])

        for report in self.reports.iterdir():
            report.unlink()
        stale = self.run_gate()
        self.assertEqual(stale.returncode, 0, stale.stdout)
        self.assertIn("2 stale", stale.stdout)

    def test_missing_baseline_is_an_error(self):
        self.add_report("report-1.html")
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
