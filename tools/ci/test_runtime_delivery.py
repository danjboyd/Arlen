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


class RuntimeTargetTests(unittest.TestCase):
    def test_supported_targets_select_a_distribution_and_architecture_specific_lock(self):
        cases = (("debian", "13", "x86_64", "debian-13-amd64"),
                 ("debian", "13", "aarch64", "debian-13-arm64"),
                 ("ubuntu", "24.04", "aarch64", "ubuntu-24.04-arm64"),
                 ("ubuntu", "26.04", "x86_64", "ubuntu-26.04-amd64"))
        for distro, version, machine, expected in cases:
            with self.subTest(target=expected), \
                    patch.object(runtime.platform, "freedesktop_os_release", return_value={"ID": distro, "VERSION_ID": version}), \
                    patch.object(runtime.platform, "machine", return_value=machine):
                self.assertEqual(runtime.target(), expected)
                self.assertEqual(runtime.lock_for_host().name, expected + ".lock.json")
                self.assertTrue(runtime.lock_for_host().is_file())

    def test_other_ubuntu_architectures_and_older_distributions_remain_unsupported(self):
        for distro, version, machine in (("ubuntu", "24.04", "x86_64"),
                                        ("ubuntu", "26.04", "aarch64"),
                                        ("ubuntu", "22.04", "aarch64"),
                                        ("debian", "12", "aarch64"),
                                        ("ubuntu", "24.04", "riscv64")):
            with self.subTest(distro=distro, version=version, machine=machine), \
                    patch.object(runtime.platform, "freedesktop_os_release", return_value={"ID": distro, "VERSION_ID": version}), \
                    patch.object(runtime.platform, "machine", return_value=machine):
                with self.assertRaisesRegex(ValueError, "supported native runtime targets"):
                    runtime.lock_for_host()


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

    def fixture(self, native=False):
        self.prefix.mkdir()
        lock_path = self.lock
        if native:
            release = runtime.platform.freedesktop_os_release()
            arch = {"x86_64": "amd64", "aarch64": "arm64"}[runtime.platform.machine()]
            lock_path = ROOT / "tools/runtime" / (release["ID"] + "-" + release["VERSION_ID"] + "-" + arch + ".lock.json")
        lock = json.loads(lock_path.read_text())
        for relative in ("System/Library/Makefiles/GNUstep.sh", "System/Tools/gnustep-config",
                         "include/objc/runtime.h", "include/dispatch/dispatch.h",
                         "Local/Library/Headers/Foundation/Foundation.h",
                         "Local/Library/Libraries/libgnustep-base.so", "lib/libobjc.so", "lib/libdispatch.so"):
            p = self.prefix / relative
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("fixture\n")
        copy = self.prefix / "gnustep-toolchain-lock" / lock_path.name
        copy.parent.mkdir()
        shutil.copy2(lock_path, copy)
        for c in lock["components"]:
            for p in c["patches"]:
                dest = copy.parent / p["path"]
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(runtime.patch_source(c, p), dest)
        prov = {"prefix": str(self.prefix), "build_host": {"os_version": "debian-13", "machine": runtime.platform.machine()},
                "lock": {"copy": str(copy.relative_to(self.prefix)), "sha256": runtime.digest(copy)},
                "components": [dict(c, resolved_commit=c["revision"], applied_patches=c["patches"]) for c in lock["components"]],
                "elf_files": {p: {"sha256": runtime.digest(self.prefix / p)} for p in
                              ("lib/libobjc.so", "lib/libdispatch.so", "Local/Library/Libraries/libgnustep-base.so")}}
        (self.prefix / runtime.PROVENANCE).write_text(json.dumps(prov))
        return prov

    def test_target_locks_preserve_pins_flags_and_three_race_patches(self):
        canonical = json.loads(self.lock.read_text())
        self.assertEqual(runtime.digest(self.lock), "df809d9d55a613726dd7475a3f45ee55a8dbfebe3913f7a442af94f66adfbb34")
        for p in (ROOT / "tools/runtime").glob("*.lock.json"):
            lock = json.loads(p.read_text())
            components = lock["components"]
            if p.name == "ubuntu-26.04-amd64.lock.json":
                compatibility = components[1]["patches"].pop()
                self.assertEqual(compatibility, {
                    "path": "patches/libdispatch/libdispatch-clang21.patch",
                    "sha256": "ffba3eb8d8e2fb14bfde3f664138e03bef8b76817834a869213a32427f85f67d"})
            if p.name == "ubuntu-24.04-arm64.lock.json":
                compatibility = components[2]["patches"].pop()
                self.assertEqual(compatibility, {
                    "path": "patches/tools-make/gnustep-config-make43.patch",
                    "sha256": "f1cf8562f3e11998100da78f0397c5fcf31e51673f2541dbbfd6d8c6ff991135"})
            self.assertEqual(canonical["components"], components)
            self.assertIn(p.stem.removesuffix(".lock").split("-")[-1], ("amd64", "arm64"))
        staged = runtime.stage_lock(self.work)
        self.assertEqual(runtime.digest(staged), runtime.digest(self.lock))
        for c in canonical["components"]:
            for p in c["patches"]:
                self.assertEqual(runtime.digest(staged.parent / p["path"]), p["sha256"])

    def test_normal_locks_require_optimized_configure_inputs_without_duplicate_objc_optimization(self):
        hashes = {
            "debian-13-amd64": "df809d9d55a613726dd7475a3f45ee55a8dbfebe3913f7a442af94f66adfbb34",
            "debian-13-arm64": "ffbc8a89b7b8ccc43bd191c166b417e7048e2034eeea5e25fb20981165c2381e",
            "ubuntu-24.04-arm64": "a4d3736287fd93c10fd47603086260c7896f97e96af05d2371de6fe3d0975c9d",
            "ubuntu-26.04-amd64": "89a81f3c29d5c421c1e8c62e5179d1951aa67a5c42a4e57ae99c9e51bcd2e125"}
        for target, sha in hashes.items():
            path = ROOT / "tools/runtime" / (target + ".lock.json")
            self.assertEqual(runtime.digest(path), sha)
            lock = json.loads(path.read_text())
            for component in lock["components"]:
                if component["name"] in ("tools-make", "libs-base"):
                    # O2 is supplied by OPTFLAG to C and ObjC; no extra ObjC O2
                    # remains after GNUstep debug=yes filters OPTFLAG.
                    self.assertEqual(component["configure_args"], ["CFLAGS=-O2", "OBJCFLAGS="])

    def test_noble_stages_existing_race_patches_and_scoped_make_query_compatibility(self):
        with patch.object(runtime, "target", return_value="ubuntu-24.04-arm64"):
            staged = runtime.stage_lock(self.work)
        lock = json.loads(staged.read_text())
        self.assertEqual(staged.name, "ubuntu-24.04-arm64.lock.json")
        self.assertEqual(runtime.digest(staged), "a4d3736287fd93c10fd47603086260c7896f97e96af05d2371de6fe3d0975c9d")
        patches = [entry for component in lock["components"] for entry in component["patches"]]
        self.assertEqual(len(patches), 4)
        for entry in patches:
            self.assertEqual(runtime.digest(staged.parent / entry["path"]), entry["sha256"])
        compatibility = lock["components"][2]["patches"].pop()
        self.assertEqual(compatibility["path"], "patches/tools-make/gnustep-config-make43.patch")
        self.assertEqual(lock["components"], json.loads(self.lock.read_text())["components"])

    def test_make43_query_patch_preserves_jobserver_assignments_and_explicit_client_flags(self):
        text = (ROOT / "tools/runtime/patches/gnustep-config-make43.patch").read_text()
        additions = [line[1:] for line in text.splitlines() if line.startswith("+") and not line.startswith("+++")]
        script = "\n".join(additions) + '\nprintf "%s" "${MAKEFLAGS-<unset>}"\n'
        cases = (("w -j4 --jobserver-auth=3,4 -- debug=yes OBJCFLAGS=-ffp-contract=off", " -j4 --jobserver-auth=3,4 -- debug=yes OBJCFLAGS=-ffp-contract=off"),
                 ("ksw -j4 -- CFLAGS=-Dwindow", "ks -j4 -- CFLAGS=-Dwindow"),
                 ("w", ""), ("s -j4 -- debug=yes", "s -j4 -- debug=yes"),
                 ("--warn-undefined-variables", "--warn-undefined-variables"),
                 ("CFLAGS=-Dwindow", "CFLAGS=-Dwindow"), (None, "<unset>"))
        for before, expected in cases:
            with self.subTest(makeflags=before):
                env = dict(os.environ)
                env.pop("MAKEFLAGS", None)
                if before is not None:
                    env["MAKEFLAGS"] = before
                result = subprocess.run(["sh", "-c", script], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)

    def test_noble_rejects_another_distribution_or_architecture_without_rewriting_provenance(self):
        original = self.fixture()
        with patch.object(runtime, "target", return_value="ubuntu-24.04-arm64"), \
                patch.object(runtime.platform, "machine", return_value="aarch64"):
            for distro, machine in (("debian-13", "aarch64"),
                                   ("ubuntu-26.04", "aarch64"),
                                   ("ubuntu-24.04", "x86_64")):
                with self.subTest(distro=distro, machine=machine):
                    prov = dict(original, build_host={"os_version": distro, "machine": machine})
                    path = self.prefix / runtime.PROVENANCE
                    path.write_text(json.dumps(prov))
                    before = path.read_bytes()
                    with self.assertRaisesRegex(ValueError, "another distribution or architecture"):
                        runtime.validate(self.prefix, full=True)
                    self.assertEqual(path.read_bytes(), before)

    def test_validation_rejects_an_old_unoptimized_component_without_relabeling_it(self):
        original = self.fixture()
        for name in ("tools-make", "libs-base"):
            with self.subTest(component=name):
                prov = json.loads(json.dumps(original))
                next(c for c in prov["components"] if c["name"] == name)["configure_args"] = []
                path = self.prefix / runtime.PROVENANCE
                path.write_text(json.dumps(prov))
                before = path.read_bytes()
                with self.assertRaisesRegex(ValueError, name + " configure_args does not match"):
                    runtime.validate(self.prefix, full=True)
                self.assertEqual(path.read_bytes(), before)

    def test_ubuntu_compatibility_patch_stages_exact_bytes_and_rejects_tampering(self):
        ubuntu_work = self.work / "ubuntu-build"
        ubuntu_work.mkdir()
        with patch.object(runtime, "target", return_value="ubuntu-26.04-amd64"):
            staged = runtime.stage_lock(ubuntu_work)
        lock = json.loads(staged.read_text())
        self.assertEqual(runtime.digest(staged), "89a81f3c29d5c421c1e8c62e5179d1951aa67a5c42a4e57ae99c9e51bcd2e125")
        for component in lock["components"]:
            for entry in component["patches"]:
                self.assertEqual(runtime.digest(staged.parent / entry["path"]), entry["sha256"])
        copied_repo = self.work / "tampered-repo"
        shutil.copytree(ROOT / "tools/runtime", copied_repo / "tools/runtime")
        shutil.copytree(ROOT / "tools/ci/tsan-toolchain", copied_repo / "tools/ci/tsan-toolchain")
        (copied_repo / "tools/runtime/patches/libdispatch-clang21.patch").write_text("substituted patch")
        bad_work = self.work / "tampered-build"
        bad_work.mkdir()
        with patch.object(runtime, "ROOT", copied_repo), patch.object(runtime, "target", return_value="ubuntu-26.04-amd64"):
            with self.assertRaisesRegex(ValueError, "repository patch checksum mismatch"):
                runtime.stage_lock(bad_work)
        with self.assertRaisesRegex(ValueError, "unsupported runtime patch path"):
            runtime.patch_source({"name": "libdispatch"}, {"path": "../libdispatch-clang21.patch"})

    def test_ubuntu_validation_rejects_old_prefix_without_compatibility_patch(self):
        prov = self.fixture()
        prov["build_host"]["os_version"] = "ubuntu-26.04"
        (self.prefix / runtime.PROVENANCE).write_text(json.dumps(prov))
        with patch.object(runtime, "target", return_value="ubuntu-26.04-amd64"):
            with self.assertRaisesRegex(ValueError, "patch/pin mismatch"):
                runtime.validate(self.prefix, full=True)

    def test_pinned_epoll_complement_preserves_all_disarmed_masks_and_high_event_bits(self):
        text = (ROOT / "tools/runtime/patches/libdispatch-clang21.patch").read_text()
        additions = [line[1:] for line in text.splitlines() if line.startswith("+") and not line.startswith("+++")]
        self.assertEqual(len(additions), 1)
        header = self.work / "epoll_mask_under_test.h"
        header.write_text("static uint32_t armed_events_under_test(dispatch_muxnote_t dmn) {\n" + additions[0] + "\n}\n")
        command = ["clang", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-Wconversion", "-Wsign-conversion",
                   "-I" + str(self.work), str(ROOT / "tests/fixtures/runtime/epoll_mask_contract.c"), "-o", str(self.work / "epoll-contract")]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([str(self.work / "epoll-contract")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pass:epoll-mask-preserves-32-bit-events 786432 cases", result.stdout)

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
        prov = self.fixture(native=True)
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

    def test_packaged_jobs_worker_selects_runtime_in_its_parent_before_exec(self):
        prov = self.fixture(native=True)
        release = runtime.platform.freedesktop_os_release()
        prov["build_host"]["os_version"] = release["ID"] + "-" + release["VERSION_ID"]
        (self.prefix / runtime.PROVENANCE).write_text(json.dumps(prov))
        (self.prefix / "System/Library/Makefiles/GNUstep.sh").write_text(":\n")
        framework = self.work / "worker-framework"
        (framework / "bin").mkdir(parents=True)
        (framework / "build").mkdir()
        shutil.copy2(ROOT / "bin/jobs-worker", framework / "bin/jobs-worker")
        tools = framework / "tools"
        tools.mkdir()
        for name in ("setup_runtime.py", "source_gnustep_env.sh", "resolve_gnustep.sh"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        shutil.copytree(ROOT / "tools/runtime", tools / "runtime")
        (framework / runtime.SELECTOR).write_text(str(self.prefix) + "\n")
        app = self.work / "packaged-app"
        binary = app / ".boomhauer/build/boomhauer-app"
        binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/sh\nprintf "%s|%s\\n" "$ARLEN_RUNTIME_PREFIX" "$LD_LIBRARY_PATH"\n')
        binary.chmod(0o755)
        arlen = framework / "build/arlen"
        arlen.write_text("#!/bin/sh\nexit 0\n")
        arlen.chmod(0o755)
        env = dict(os.environ)
        env.pop("ARLEN_RUNTIME_PREFIX", None)
        result = subprocess.run([str(framework / "bin/jobs-worker"), "--app-root", str(app), "--framework-root", str(framework)],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith(str(self.prefix) + "|" + str(self.prefix) + "/lib:"), result.stdout)

    def test_functional_ci_selects_prefix_and_private_defaults_without_setup(self):
        prov = self.fixture(native=True)
        release = runtime.platform.freedesktop_os_release()
        prov["build_host"]["os_version"] = release["ID"] + "-" + release["VERSION_ID"]
        (self.prefix / runtime.PROVENANCE).write_text(json.dumps(prov))
        (self.prefix / "System/Library/Makefiles/GNUstep.sh").write_text(":\n")
        conf = self.prefix / "etc/GNUstep/GNUstep.conf"
        conf.parent.mkdir(parents=True)
        conf.write_text('GNUSTEP_SYSTEM_ROOT=' + str(self.prefix / "System") + '\n')
        env = dict(os.environ, ARLEN_RUNTIME_PREFIX=str(self.prefix), ARLEN_NORMAL_RUNTIME_STATE=str(self.work / "ci-state"),
                   GITHUB_ENV=str(self.work / "github-env"))
        result = subprocess.run(["bash", str(ROOT / "tools/ci/setup_normal_runtime.sh")], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        saved = (self.work / "github-env").read_text()
        self.assertIn("ARLEN_RUNTIME_PREFIX=" + str(self.prefix), saved)
        self.assertIn("ARLEN_GNUSTEP_CONFIG_FILE=" + str(self.work / "ci-state/GNUstep.conf"), saved)
        config = self.work / "ci-state/GNUstep.conf"
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        self.assertIn(str(self.work / "ci-state/Defaults"), config.read_text())
        self.assertIn(str(self.work / "ci-state/absent-user.conf"), config.read_text())
        self.assertIn(str(self.prefix / "System"), config.read_text())

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
