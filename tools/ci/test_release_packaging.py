#!/usr/bin/env python3
"""Regression checks for release packaging and managed-toolchain env setup."""

import os
import re
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


class WindowsBundledDllListTests(unittest.TestCase):
    LIST = REPO_ROOT / "tools/release/windows_bundled_dlls.txt"
    SHA256 = r"^[0-9a-f]{64}$"

    def _lines(self, list_path, toolchain, sha256):
        script = (REPO_ROOT / "tools/release/package_framework.sh").read_text()
        match = re.search(r"^windows_bundled_dll_lines\(\) \{\n.*?^\}\n", script, re.S | re.M)
        self.assertIsNotNone(match, "windows_bundled_dll_lines() not found")
        return subprocess.run(["bash", "-c", match.group(0) + 'windows_bundled_dll_lines "$1" "$2" "$3"\n',
                               "test", str(list_path), toolchain, sha256],
                              capture_output=True, text=True)

    def test_list_is_well_formed(self):
        sections = {}
        current = None
        for raw in self.LIST.read_text().splitlines():
            fields = raw.split()
            if not fields or fields[0].startswith("#"):
                continue
            if fields[0] == "toolchain":
                self.assertEqual(3, len(fields), raw)
                self.assertRegex(fields[2], self.SHA256, raw)
                self.assertNotIn((fields[1], fields[2]), sections, f"duplicate section: {raw}")
                current = (fields[1], fields[2])
                sections[current] = 0
                continue
            self.assertEqual("dll", fields[0], raw)
            self.assertIsNotNone(current, f"dll line before any toolchain line: {raw}")
            self.assertEqual(5, len(fields), raw)
            self.assertTrue(fields[1].startswith("https://"), raw)
            self.assertRegex(fields[2], self.SHA256, raw)
            self.assertRegex(fields[4], self.SHA256, raw)
            sections[current] += 1
        self.assertTrue(sections)
        for section, count in sections.items():
            self.assertGreater(count, 0, f"toolchain section without DLLs: {section}")

    def test_selects_only_the_matching_toolchain_section(self):
        with tempfile.TemporaryDirectory() as base:
            path = Path(base) / "dlls.txt"
            two = f"dll https://x/two.zst {'3' * 64} bin/two.dll {'4' * 64}"
            path.write_text("# comment\n"
                            f"toolchain 1.0 {'a' * 64}\n"
                            f"dll https://x/one.zst {'1' * 64} bin/one.dll {'2' * 64}\n"
                            "\n"
                            f"toolchain 1.0 {'b' * 64}\n"
                            f"{two}\n")
            result = self._lines(path, "1.0", "b" * 64)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual([two], result.stdout.splitlines())
            # A rebuilt toolchain republished under the same version has no section yet.
            result = self._lines(path, "1.0", "c" * 64)
            self.assertEqual(1, result.returncode)
            self.assertIn("no section for toolchain 1.0", result.stderr)

    def test_unknown_line_kind_fails(self):
        with tempfile.TemporaryDirectory() as base:
            path = Path(base) / "dlls.txt"
            path.write_text(f"toolchain 1.0 {'a' * 64}\nlib whatever\n")
            result = self._lines(path, "1.0", "a" * 64)
            self.assertEqual(2, result.returncode)
            self.assertIn("unknown line kind lib", result.stderr)


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
