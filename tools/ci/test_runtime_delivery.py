#!/usr/bin/env python3
"""Runtime delivery safety/selection regressions; no download or native build."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("arlen_runtime", ROOT / "tools/setup_runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="arlen-runtime-test-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.prefix = self.work / "runtime"
        self.lock = ROOT / "tools/runtime/debian-13-amd64.lock.json"
        self.target_patch = patch.object(runtime, "target", return_value="debian-13-amd64")
        self.target_patch.start()
        self.addCleanup(self.target_patch.stop)

    def fixture(self):
        self.prefix.mkdir()
        lock = json.loads(self.lock.read_text())
        for relative in ("System/Library/Makefiles/GNUstep.sh", "System/Tools/gnustep-config",
                         "include/objc/runtime.h", "include/dispatch/dispatch.h",
                         "Local/Library/Headers/Foundation/Foundation.h",
                         "Local/Library/Libraries/libgnustep-base.so", "lib/libobjc.so", "lib/libdispatch.so"):
            p = self.prefix / relative
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("fixture\n")
        copy = self.prefix / "gnustep-toolchain-lock/debian-13-amd64.lock.json"
        copy.parent.mkdir()
        shutil.copy2(self.lock, copy)
        for c in lock["components"]:
            for p in c["patches"]:
                dest = copy.parent / p["path"]
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / "tools/ci/tsan-toolchain" / (c["name"] + ".patch"), dest)
        prov = {"prefix": str(self.prefix), "build_host": {"os_version": "debian-13", "machine": runtime.platform.machine()},
                "lock": {"copy": str(copy.relative_to(self.prefix)), "sha256": runtime.digest(copy)},
                "components": [dict(c, resolved_commit=c["revision"], applied_patches=c["patches"]) for c in lock["components"]],
                "elf_files": {p: {"sha256": runtime.digest(self.prefix / p)} for p in
                              ("lib/libobjc.so", "lib/libdispatch.so", "Local/Library/Libraries/libgnustep-base.so")}}
        (self.prefix / runtime.PROVENANCE).write_text(json.dumps(prov))
        return prov

    def test_each_target_lock_has_identical_component_pins_flags_and_patches(self):
        canonical = json.loads(self.lock.read_text())
        self.assertEqual(runtime.digest(self.lock), "2bc1f69a6f2b4073adaa0c8892204995bc2b0672d1d136ffb2af611cd5d15058")
        for p in (ROOT / "tools/runtime").glob("*.lock.json"):
            lock = json.loads(p.read_text())
            self.assertEqual(canonical["components"], lock["components"])
            self.assertIn(p.stem.removesuffix(".lock").split("-")[-1], ("amd64", "arm64"))
        staged = runtime.stage_lock(self.work)
        self.assertEqual(runtime.digest(staged), runtime.digest(self.lock))
        for c in canonical["components"]:
            for p in c["patches"]:
                self.assertEqual(runtime.digest(staged.parent / p["path"]), p["sha256"])

    def test_full_validation_rejects_changed_binary_and_never_overwrites_selector(self):
        self.fixture()
        self.assertEqual(runtime.validate(self.prefix, full=True), self.prefix)
        app = self.work / "framework"
        app.mkdir()
        runtime.select(self.prefix, app)
        before = (app / runtime.SELECTOR).read_bytes()
        (self.prefix / "lib/libobjc.so").write_text("changed\n")
        with self.assertRaisesRegex(ValueError, "ELF checksum"):
            runtime.select(self.prefix, app)
        self.assertEqual((app / runtime.SELECTOR).read_bytes(), before)

    def test_moved_or_foreign_runtime_is_rejected(self):
        prov = self.fixture()
        prov["prefix"] = "/another/original/prefix"
        (self.prefix / runtime.PROVENANCE).write_text(json.dumps(prov))
        with self.assertRaisesRegex(ValueError, "moved"):
            runtime.validate(self.prefix)
        prov["prefix"] = str(self.prefix)
        prov["build_host"]["os_version"] = "ubuntu-26.04"
        (self.prefix / runtime.PROVENANCE).write_text(json.dumps(prov))
        with self.assertRaisesRegex(ValueError, "another distribution"):
            runtime.validate(self.prefix)

    def test_existing_invalid_prefix_is_preserved_without_fetch_or_builder(self):
        root = self.work / "runtimes"
        dest = root / ("debian-13-amd64-" + runtime.digest(self.lock)[:16])
        dest.mkdir(parents=True)
        (dest / "partial-build").write_text("preserve")
        with patch.object(runtime, "builder", side_effect=AssertionError("must not fetch")):
            with self.assertRaises(OSError):
                runtime.build(root, 1)
        self.assertEqual((dest / "partial-build").read_text(), "preserve")

    def test_checksum_mismatch_never_extracts_or_executes_builder(self):
        fake = self.work / "fake.tar.gz"
        fake.write_bytes(b"not the pinned executable source")
        with fake.open("rb") as response, patch.object(runtime.urllib.request, "urlopen", return_value=response):
            with self.assertRaisesRegex(ValueError, "archive checksum"):
                runtime.builder(self.work)
        self.assertFalse((self.work / "builder").exists())

    def test_unsafe_prefix_roots_are_rejected_before_fetch(self):
        for p in ("/", "/usr/arlen", "/opt/gnustep-cli/arlen", "/tmp/runtime with spaces"):
            with self.subTest(p=p), self.assertRaises(ValueError):
                runtime.build(p, 1)

    def test_selector_overrides_ambient_toolchain_but_explicit_runtime_wins(self):
        prov = self.fixture()
        release = runtime.platform.freedesktop_os_release()
        prov["build_host"]["os_version"] = release["ID"] + "-" + release["VERSION_ID"]
        (self.prefix / runtime.PROVENANCE).write_text(json.dumps(prov))
        framework = self.work / "framework"
        tools = framework / "tools"
        tools.mkdir(parents=True)
        for name in ("setup_runtime.py", "resolve_gnustep.sh", "source_gnustep_env.sh"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        shutil.copytree(ROOT / "tools/runtime", tools / "runtime")
        (framework / runtime.SELECTOR).write_text(str(self.prefix) + "\n")
        (self.prefix / "System/Library/Makefiles/GNUstep.sh").write_text('export GNUSTEP_MAKEFILES="' + str(self.prefix) + '/System/Library/Makefiles"\n')
        env = dict(os.environ, GNUSTEP_SH="/usr/ambient/GNUstep.sh", GNUSTEP_MAKEFILES="/wrong/Makefiles")
        env.pop("ARLEN_RUNTIME_PREFIX", None)
        result = subprocess.run(["bash", "-c", 'source "$1" && printf "%s|%s|%s\\n" "$GNUSTEP_SH" "$GNUSTEP_MAKEFILES" "$LD_LIBRARY_PATH"',
                                 "bash", str(tools / "source_gnustep_env.sh")], env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith(str(self.prefix) + "/System/Library/Makefiles/GNUstep.sh|"))
        self.assertIn("|" + str(self.prefix) + "/lib:", result.stdout)
        env["ARLEN_RUNTIME_PREFIX"] = str(self.work / "missing-explicit")
        result = subprocess.run(["bash", str(tools / "resolve_gnustep.sh")], env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b"/usr/GNUstep", result.stdout)

    def test_no_setup_rejects_unpatched_runtime_without_network_and_preserves_release(self):
        framework = self.work / "pkg/arlen-1.2.3"
        (framework / "bin").mkdir(parents=True)
        (framework / "tools").mkdir()
        (framework / "src/Arlen").mkdir(parents=True)
        (framework / ".arlen-dist").write_text("kind=source\nversion=1.2.3\n")
        (framework / "GNUmakefile").touch()
        for name in ("arlen", "arlen-doctor", "boomhauer"):
            p = framework / "bin" / name
            p.write_text("#!/bin/sh\nexit 0\n")
            p.chmod(0o755)
        for name in ("setup_runtime.py", "source_gnustep_env.sh", "resolve_gnustep.sh", "arlen.m"):
            shutil.copy2(ROOT / "tools" / name, framework / "tools" / name)
        shutil.copytree(ROOT / "tools/runtime", framework / "tools/runtime")
        archive = self.work / "release.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(framework, arcname="arlen-1.2.3")
        home = self.work / "home"
        home.mkdir()
        prefix = home / "arlen"
        bin_dir = home / "bin"
        mocks = self.work / "mocks"
        mocks.mkdir()
        # Any network or apt attempt fails and leaves an observable record.
        for name in ("curl", "apt-get", "sudo"):
            p = mocks / name
            p.write_text('#!/bin/sh\necho called >> "$ARLEN_TEST_NETWORK_MARKER"\nexit 91\n')
            p.chmod(0o755)
        env = dict(os.environ, HOME=str(home), SHELL="/bin/bash", PATH=str(mocks) + ":" + os.environ["PATH"],
                   ARLEN_TEST_NETWORK_MARKER=str(self.work / "network-called"), GNUSTEP_SH="/unpatched/missing/GNUstep.sh")
        env.pop("ARLEN_RUNTIME_PREFIX", None)
        command = ["bash", str(ROOT / "tools/install.sh"), "--archive", str(archive), "--prefix", str(prefix),
                   "--bin-dir", str(bin_dir), "--no-modify-path"]
        initial = subprocess.run(command + ["--no-build"], env=env, capture_output=True, text=True)
        self.assertEqual(initial.returncode, 0, initial.stderr)
        (prefix / "1.2.3/preserved").write_text("old release")
        before = (bin_dir / "arlen").read_bytes()
        result = subprocess.run(command + ["--no-setup"], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--no-setup never downloads/builds a runtime", result.stderr)
        self.assertEqual((prefix / "1.2.3/preserved").read_text(), "old release")
        self.assertEqual((bin_dir / "arlen").read_bytes(), before)
        self.assertEqual(os.readlink(prefix / "current"), "1.2.3")
        self.assertFalse((self.work / "network-called").exists())

    def test_unconfigured_release_refuses_ambient_fallback_without_installing(self):
        framework = self.work / "framework"
        tools = framework / "tools"
        tools.mkdir(parents=True)
        for name in ("setup_runtime.py", "source_gnustep_env.sh", "resolve_gnustep.sh"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        (framework / ".arlen-dist").write_text("kind=source\n")
        env = dict(os.environ)
        env.pop("ARLEN_RUNTIME_PREFIX", None)
        result = subprocess.run(["bash", "-c", 'source "$1"', "bash", str(tools / "source_gnustep_env.sh")], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires its patched runtime", result.stderr)
        self.assertFalse((framework / runtime.SELECTOR).exists())


if __name__ == "__main__":
    unittest.main()
