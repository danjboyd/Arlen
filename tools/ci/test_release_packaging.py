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
            self.assertIn("arlen-9.8.7/tools/setup_runtime.py", names)
            self.assertIn("arlen-9.8.7/tools/ci/setup_normal_runtime.sh", names)
            self.assertIn("arlen-9.8.7/tests/fixtures/runtime/icu_runtime_contract.m", names)
            self.assertIn("arlen-9.8.7/tools/runtime/patches/libdispatch-clang21.patch", names)
            self.assertIn("arlen-9.8.7/tests/fixtures/runtime/epoll_mask_contract.c", names)
            for target in ("debian-13-amd64", "debian-13-arm64", "ubuntu-26.04-amd64"):
                self.assertIn(f"arlen-9.8.7/tools/runtime/{target}.lock.json", names)
            for component in ("libobjc2", "libdispatch", "libs-base"):
                self.assertIn(f"arlen-9.8.7/tools/ci/tsan-toolchain/{component}.patch", names)
            self.assertNotIn("arlen-9.8.7/.arlen-runtime", names)
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


class LinuxBootstrapTrustTests(unittest.TestCase):
    def test_matching_remote_checksum_cannot_replace_pinned_bootstrap(self):
        installer = (REPO_ROOT / "tools/install.sh").read_text()
        start = installer.index("  if ! linux_toolchain_ready; then\n")
        end = installer.index("\n  fi\n  linux_toolchain_ready", start) + len("\n  fi")
        fragment = installer[start:end]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / "substitute-bootstrap.sh"
            marker = root / "bootstrap-executed"
            payload.write_text('#!/bin/sh\nprintf executed > "$ARLEN_TEST_BOOTSTRAP_MARKER"\n')
            script = r'''
set -euo pipefail
linux_toolchain_ready() { return 1; }
die() { printf '%s\n' "$*" >&2; exit 1; }
sha256_of() {
  python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}
curl() {
  local output='' url=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o) output="$2"; shift 2 ;;
      -*) shift ;;
      *) url="$1"; shift ;;
    esac
  done
  case "$url" in
    *.sha256) printf '%s  gnustep-bootstrap.sh\n' "$(sha256_of "$ARLEN_TEST_BOOTSTRAP_PAYLOAD")" > "$output" ;;
    *) cp "$ARLEN_TEST_BOOTSTRAP_PAYLOAD" "$output" ;;
  esac
}
setup_fragment() {
''' + fragment + '\n}\nsetup_fragment\n'
            environment = dict(os.environ, work_dir=directory,
                               ARLEN_TEST_BOOTSTRAP_PAYLOAD=str(payload),
                               ARLEN_TEST_BOOTSTRAP_MARKER=str(marker))
            result = subprocess.run(["bash", "-c", script], env=environment,
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("GNUstep bootstrap checksum mismatch", result.stderr)
            self.assertFalse(marker.exists(), "untrusted bootstrap must not execute")


class InstallPathHintTests(unittest.TestCase):
    def test_installer_persists_path_for_fresh_shells_without_duplicate_entries(self):
        cases = [
            ("/bin/zsh", None, (".zprofile", ".zshrc")),
            ("/bin/bash", None, (".profile", ".bashrc")),
            ("/bin/bash", ".bash_profile", (".bash_profile", ".bashrc")),
            ("/bin/bash", ".bash_login", (".bash_login", ".bashrc")),
            ("/bin/sh", None, (".profile",)),
        ]
        with tempfile.TemporaryDirectory() as out:
            subprocess.run(
                ["bash", str(REPO_ROOT / "tools/release/package_framework.sh"),
                 "--version", "9.8.7", "--kind", "source", "--out", out],
                check=True, cwd=REPO_ROOT, stdout=subprocess.DEVNULL)
            # Exercise the portable profile contract with a source archive on
            # either host OS; no build or prerequisite installation is needed.
            stubs = Path(out) / "stubs"
            stubs.mkdir()
            uname = stubs / "uname"
            uname.write_text("#!/bin/sh\ncase \"$1\" in -s) echo Linux;; -m) echo x86_64;; esac\n")
            uname.chmod(0o755)
            for shell, existing, profiles in cases:
                with self.subTest(shell=shell, existing=existing), tempfile.TemporaryDirectory(dir=out) as home:
                    if existing:
                        (Path(home) / existing).write_text("# existing user configuration\n")
                    bin_dir = Path(home) / "bin with ' quote"
                    command = [
                        "bash", str(REPO_ROOT / "tools/install.sh"),
                        "--archive", str(Path(out) / "arlen-9.8.7.tar.gz"), "--no-build",
                        "--prefix", str(Path(home) / "prefix"), "--bin-dir", str(bin_dir),
                    ]
                    env = {"PATH": f"{stubs}:/usr/bin:/bin", "HOME": home,
                           "SHELL": shell, "TMPDIR": home}
                    for _ in range(2):
                        subprocess.run(command, env=env, check=True,
                                       capture_output=True, text=True)
                    for profile in profiles:
                        path = Path(home) / profile
                        self.assertEqual(path.read_text().count("# Arlen launcher\n"), 1)
                        result = subprocess.run(
                            ["bash", "--noprofile", "--norc", "-c",
                             '. "$1"; cd /; command -v arlen', "test", str(path)],
                            env=env, check=True, capture_output=True, text=True)
                        self.assertEqual(Path(result.stdout.strip()).resolve(),
                                         (bin_dir / "arlen").resolve())
                    if existing:
                        self.assertTrue((Path(home) / existing).read_text().startswith(
                            "# existing user configuration\n"))


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


@unittest.skipUnless(
    os.uname().sysname == "Darwin"
    and Path("/opt/homebrew/opt/openssl@3/include/openssl").is_dir(),
    "requires macOS with Homebrew openssl@3",
)
class AppleBrewPrefixTests(unittest.TestCase):
    def test_installed_opt_link_works_with_uncached_home_and_offline_brew(self):
        with tempfile.TemporaryDirectory() as home:
            stub_dir = Path(home) / "stub"
            stub_dir.mkdir()
            marker = Path(home) / "brew-called"
            brew = stub_dir / "brew"
            brew.write_text("#!/bin/sh\nprintf called > \"$BREW_MARKER\"\nexit 42\n")
            brew.chmod(0o755)
            result = subprocess.run(
                ["bash", "-c", 'source "$1"; aln_platform_first_brew_prefix openssl@3',
                 "test", str(REPO_ROOT / "tools/platform.sh")],
                env={"PATH": f"{stub_dir}:/usr/bin:/bin", "HOME": home,
                     "BREW_MARKER": str(marker)},
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "/opt/homebrew/opt/openssl@3")
            self.assertFalse(marker.exists(), "installed formula must not query Brew API")


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
