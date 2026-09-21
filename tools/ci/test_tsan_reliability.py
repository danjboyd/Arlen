#!/usr/bin/env python3
"""Behavioral checks for TSAN evidence and unavailable-tool handling."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from tsan_runtime_diagnostics import classify_run
from check_sanitizer_suppressions import validate_tsan_patterns

ROOT = Path(__file__).resolve().parents[2]


class TSANReliabilityTests(unittest.TestCase):
    def test_canary_requires_named_race_and_expected_exit(self):
        log = "probe-complete:canary\nWARNING: ThreadSanitizer: data race\nALNTSANCanaryCounter"
        self.assertTrue(classify_run("canary", True, 66, log)["valid"])
        for rc, text in ((0, log), (66, "probe-complete:canary"),
                         (66, log.replace("ALNTSANCanaryCounter", "unrelated")),
                         (124, log), (66, log.replace("probe-complete:canary", ""))):
            self.assertFalse(classify_run("canary", True, rc, text)["valid"])

    def test_raw_findings_are_retained_but_suppressed_findings_fail(self):
        log = "probe-complete:queue\nWARNING: ThreadSanitizer: data race"
        self.assertTrue(classify_run("queue", False, 66, log)["valid"])
        self.assertFalse(classify_run("queue", True, 66, log)["valid"])
        self.assertFalse(classify_run("queue", True, 0, log)["valid"])
        self.assertFalse(classify_run("queue", False, -11, log)["valid"])

    def test_unavailable_tsan_never_passes_or_falls_back_by_default(self):
        for script, directory in (("run_phase5e_tsan_experimental.sh", "tsan"),
                                  ("run_linux_thread_race_nightly.sh", "phase10m_thread_race")):
            with self.subTest(script=script), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                scripts = root / "tools/ci"
                scripts.mkdir(parents=True)
                shutil.copy(ROOT / "tools/ci" / script, scripts / script)
                (root / "tools/source_gnustep_env.sh").write_text(":\n")
                fake = root / "fakebin"
                fake.mkdir()
                for name, body in (("clang", "echo /nonexistent/arlen/libtsan.so"),
                                   ("make", "exit 0"),
                                   ("valgrind", "touch fallback-ran; exit 0")):
                    path = fake / name
                    path.write_text("#!/bin/sh\n" + body + "\n")
                    path.chmod(0o755)
                env = os.environ.copy()
                for key in ("LD_PRELOAD", "XCTEST_LD_PRELOAD", "ARLEN_REQUIRE_TSAN",
                            "ARLEN_TSAN_ARTIFACT_DIR", "ARLEN_PHASE10M_THREAD_ARTIFACT_DIR"):
                    env.pop(key, None)
                env["PATH"] = str(fake) + ":" + env["PATH"]
                result = subprocess.run(["bash", str(scripts / script)], cwd=root, env=env,
                                        text=True, capture_output=True, timeout=15)
                self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
                summary = json.loads((root / "build/sanitizers" / directory / "summary.json").read_text())
                self.assertEqual(summary["status"], "unavailable")
                self.assertFalse((root / "fallback-ran").exists())

    def test_nightly_runs_diagnostics_after_failure_and_preserves_primary_status(self):
        for tsan_rc, diagnostic_rc, expected_rc, reason in (
                (88, 1, 88, "tsan_lane_failure"),
                (0, 1, 1, "tsan_diagnostic_control_failure"),
                (0, 0, 0, "")):
            with self.subTest(tsan_rc=tsan_rc, diagnostic_rc=diagnostic_rc), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                scripts = root / "tools/ci"
                scripts.mkdir(parents=True)
                script = scripts / "run_linux_thread_race_nightly.sh"
                shutil.copy(ROOT / "tools/ci" / script.name, script)
                (root / "tools/source_gnustep_env.sh").write_text(":\n")
                (scripts / "run_phase5e_tsan_experimental.sh").write_text(
                    f"echo original-tsan-evidence\nexit {tsan_rc}\n")
                (scripts / "tsan_runtime_diagnostics.py").write_text(
                    "from pathlib import Path\n"
                    "Path('diagnostics-ran').touch()\n"
                    f"raise SystemExit({diagnostic_rc})\n")
                fake = root / "fakebin"
                fake.mkdir()
                runtime = root / "libtsan.so"
                runtime.touch()
                for name, body in (("clang", f"echo '{runtime}'"), ("make", "exit 0")):
                    path = fake / name
                    path.write_text("#!/bin/sh\n" + body + "\n")
                    path.chmod(0o755)
                env = os.environ.copy()
                for key in ("LD_PRELOAD", "XCTEST_LD_PRELOAD", "ARLEN_PHASE10M_THREAD_ARTIFACT_DIR"):
                    env.pop(key, None)
                env["PATH"] = str(fake) + ":" + env["PATH"]
                result = subprocess.run(["bash", str(script)], cwd=root, env=env,
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, expected_rc, result.stdout + result.stderr)
                self.assertTrue((root / "diagnostics-ran").exists())
                artifacts = root / "build/sanitizers/phase10m_thread_race"
                summary = json.loads((artifacts / "summary.json").read_text())
                self.assertEqual(summary["reason"], reason)
                self.assertIn("original-tsan-evidence", (artifacts / "thread_race.log").read_text())

    def test_registry_rejects_untracked_patterns_and_missing_evidence(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            suppression = root / "tsan.supp"
            suppression.write_text("race:example\n")
            evidence = root / "evidence.md"
            evidence.write_text("reproducer and review\n")
            entry = {"id": "example", "status": "active", "sanitizer": "thread",
                     "patterns": ["race:example"], "evidence": "evidence.md"}
            payload = {"suppressions": [entry]}
            self.assertEqual(validate_tsan_patterns(payload, suppression, root), [])
            suppression.write_text("race:example\nrace:untracked\n")
            self.assertTrue(validate_tsan_patterns(payload, suppression, root))
            suppression.write_text("race:example\n")
            evidence.unlink()
            self.assertTrue(validate_tsan_patterns(payload, suppression, root))


if __name__ == "__main__":
    unittest.main()
