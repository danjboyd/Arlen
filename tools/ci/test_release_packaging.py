#!/usr/bin/env python3
"""Regression checks for release packaging and managed-toolchain env setup."""

import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


class SourceArchiveTests(unittest.TestCase):
    def test_source_archive_layout(self):
        with tempfile.TemporaryDirectory() as out:
            subprocess.run(
                ["bash", str(REPO_ROOT / "tools/release/package_framework.sh"),
                 "--version", "9.8.7", "--kind", "source", "--out", out],
                check=True, cwd=REPO_ROOT, stdout=subprocess.DEVNULL)
            archive = Path(out) / "arlen-9.8.7.tar.gz"
            self.assertTrue(archive.is_file())

            with tarfile.open(archive) as tar:
                names = tar.getnames()
                dist = tar.extractfile("arlen-9.8.7/.arlen-dist").read().decode()

            self.assertTrue(all(n == "arlen-9.8.7" or n.startswith("arlen-9.8.7/") for n in names))
            self.assertIn("arlen-9.8.7/bin/arlen", names)
            self.assertIn("arlen-9.8.7/tools/install.sh", names)
            self.assertIn("arlen-9.8.7/vendor/tools-xctest/GNUmakefile", names)
            self.assertFalse(any("/.git/" in n or n.endswith("/.git") for n in names))
            self.assertFalse(any(n.startswith("arlen-9.8.7/vendor/gnustep-cli-new/") for n in names))
            self.assertIn("version=9.8.7\n", dist)
            self.assertIn("kind=source\n", dist)

            sums = (Path(out) / "SHA256SUMS").read_text()
            self.assertRegex(sums, r"^[0-9a-f]{64}  arlen-9\.8\.7\.tar\.gz\n$")

    def test_rejects_bad_version(self):
        result = subprocess.run(
            ["bash", str(REPO_ROOT / "tools/release/package_framework.sh"),
             "--version", "latest", "--kind", "source"],
            cwd=REPO_ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)


class InstallPathHintTests(unittest.TestCase):
    def test_path_hint_names_the_login_shell_startup_file(self):
        bash_rc = "~/.bash_profile" if os.uname().sysname == "Darwin" else "~/.bashrc"
        expected = {"/bin/zsh": "~/.zprofile", "/bin/bash": bash_rc,
                    "/bin/sh": "~/.profile"}
        with tempfile.TemporaryDirectory() as out:
            subprocess.run(
                ["bash", str(REPO_ROOT / "tools/release/package_framework.sh"),
                 "--version", "9.8.7", "--kind", "source", "--out", out],
                check=True, cwd=REPO_ROOT, stdout=subprocess.DEVNULL)
            for shell, rc in expected.items():
                with self.subTest(shell=shell):
                    result = subprocess.run(
                        ["bash", str(REPO_ROOT / "tools/install.sh"),
                         "--archive", str(Path(out) / "arlen-9.8.7.tar.gz"), "--no-build",
                         "--prefix", str(Path(out) / "prefix"),
                         "--bin-dir", str(Path(out) / "bin")],
                        env={"PATH": "/usr/bin:/bin", "HOME": out, "SHELL": shell,
                             "TMPDIR": out},
                        check=True, capture_output=True, text=True)
                    self.assertIn(f">> {rc}\n", result.stdout + result.stderr)


class ManagedToolchainEnvTests(unittest.TestCase):
    def _fake_root(self, base, managed):
        root = Path(base) / "gs"
        makefiles = root / "System/Library/Makefiles"
        makefiles.mkdir(parents=True)
        (makefiles / "GNUstep.sh").write_text("GNUSTEP_FAKE_SOURCED=1\n")
        (root / "lib").mkdir()
        if managed:
            (root / "toolchain-manifest.json").write_text("{}\n")
        return root

    def _ld_path_after_source(self, gnustep_sh):
        env = {"PATH": "/usr/bin:/bin", "HOME": "/nonexistent",
               "GNUSTEP_SH": str(gnustep_sh), "LD_LIBRARY_PATH": "/existing"}
        script = (f"source '{REPO_ROOT}/tools/source_gnustep_env.sh' && "
                  "printf '%s' \"$LD_LIBRARY_PATH\"")
        return subprocess.run(["bash", "-c", script], env=env, check=True,
                              capture_output=True, text=True).stdout

    def test_managed_root_lib_is_prepended(self):
        with tempfile.TemporaryDirectory() as base:
            root = self._fake_root(base, managed=True)
            ld = self._ld_path_after_source(root / "System/Library/Makefiles/GNUstep.sh")
            first, rest = ld.split(":", 1)
            self.assertEqual(Path(first).resolve(), (root / "lib").resolve())
            self.assertEqual(rest, "/existing")

    def test_unmanaged_root_is_left_alone(self):
        with tempfile.TemporaryDirectory() as base:
            root = self._fake_root(base, managed=False)
            ld = self._ld_path_after_source(root / "System/Library/Makefiles/GNUstep.sh")
            self.assertEqual(ld, "/existing")


@unittest.skipUnless(os.uname().sysname == "Linux", "Linux build path only")
class BuildReleaseEnvTests(unittest.TestCase):
    """build_release.sh from a shell that never sourced GNUstep.sh (issue 181)."""

    def test_sources_gnustep_env_and_prepares_app_with_any_sources(self):
        with tempfile.TemporaryDirectory() as base:
            base = Path(base)
            gnustep_sh = base / "gs/System/Library/Makefiles/GNUstep.sh"
            gnustep_sh.parent.mkdir(parents=True)
            gnustep_sh.write_text("export GNUSTEP_FAKE_SOURCED=1\n")

            framework = base / "framework"
            (framework / "src/Arlen").mkdir(parents=True)
            (framework / "GNUmakefile").write_text("")
            (framework / "tools").mkdir()
            for name in ("source_gnustep_env.sh", "resolve_gnustep.sh"):
                (framework / "tools" / name).write_text(
                    (REPO_ROOT / "tools" / name).read_text())
            calls = base / "calls.log"
            (framework / "bin").mkdir()
            boomhauer = framework / "bin/boomhauer"
            boomhauer.write_text(
                "#!/usr/bin/env bash\n"
                f"echo \"boomhauer sourced=${{GNUSTEP_FAKE_SOURCED:-}}\" >> '{calls}'\n"
                "mkdir -p \"$ARLEN_APP_ROOT/.boomhauer/build\"\n"
                "printf '#!/bin/sh\\n' > \"$ARLEN_APP_ROOT/.boomhauer/build/boomhauer-app\"\n"
                "chmod +x \"$ARLEN_APP_ROOT/.boomhauer/build/boomhauer-app\"\n")
            boomhauer.chmod(0o755)

            stubs = base / "stubs"
            stubs.mkdir()
            make = stubs / "make"
            make.write_text(
                "#!/usr/bin/env bash\n"
                f"echo \"make sourced=${{GNUSTEP_FAKE_SOURCED:-}}\" >> '{calls}'\n")
            make.chmod(0o755)

            # Like examples/tech_demo: sources, but no src/main.m.
            app = base / "app"
            (app / "config").mkdir(parents=True)
            (app / "config/app.plist").write_text("{}\n")
            (app / "src").mkdir()
            (app / "src/demo_server.m").write_text("")

            subprocess.run(
                ["bash", str(REPO_ROOT / "tools/deploy/build_release.sh"),
                 "--app-root", str(app), "--framework-root", str(framework),
                 "--releases-dir", str(base / "releases"), "--release-id", "r1",
                 "--allow-missing-certification"],
                env={"PATH": f"{stubs}:/usr/bin:/bin", "HOME": str(base),
                     "GNUSTEP_SH": str(gnustep_sh)},
                check=True, capture_output=True, text=True)

            self.assertEqual(calls.read_text().splitlines(),
                             ["make sourced=1", "boomhauer sourced=1"])
            self.assertTrue(
                (base / "releases/r1/app/.boomhauer/build/boomhauer-app").is_file())


if __name__ == "__main__":
    unittest.main()
