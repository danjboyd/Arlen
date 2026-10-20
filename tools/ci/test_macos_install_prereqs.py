#!/usr/bin/env python3
"""Host-safe checks for Apple release prerequisite detection."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "tools/release/install_macos_prereqs.sh"


@unittest.skipUnless(os.uname().sysname == "Darwin" and os.uname().machine == "arm64",
                     "requires Apple Silicon macOS")
class MacosInstallPrereqTests(unittest.TestCase):
    def run_helper(self, path, setup="off"):
        return subprocess.run(
            ["bash", "-c", 'source "$1"; aln_install_macos_prereqs "$2" 0',
             "test", str(HELPER), setup],
            env={"PATH": path, "HOME": self.tempdir.name},
            capture_output=True, text=True,
        )

    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.stub_dir = Path(self.tempdir.name) / "stubs"
        self.stub_dir.mkdir()

    def stub(self, name, body):
        path = self.stub_dir / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def test_installed_toolchain_and_openssl_work_with_fresh_home(self):
        if not Path("/opt/homebrew/opt/openssl@3/include/openssl").is_dir():
            self.skipTest("Homebrew openssl@3 is not installed on this host")
        result = self.run_helper(f"{self.stub_dir}:/usr/bin:/bin")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_apple_sdk_reports_install_step(self):
        self.stub("xcrun", "exit 1\n")
        result = self.run_helper(f"{self.stub_dir}:/usr/bin:/bin")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("xcode-select --install", result.stderr)

    def test_unsupported_macos_version_fails_before_install(self):
        self.stub("sw_vers", "printf '13.7.6\\n'\n")
        result = self.run_helper(f"{self.stub_dir}:/usr/bin:/bin")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires macOS 14 or newer", result.stderr)


if __name__ == "__main__":
    unittest.main()
