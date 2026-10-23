#!/usr/bin/env python3
"""Build/select Arlen's patched normal GNUstep runtime using the existing builder.

No implicit setup: only the `build` command downloads or compiles. Prefixes are
absolute, immutable and deliberately not relocatable. Never pass an existing
prefix to the upstream builder (which otherwise deletes it).
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
BUILDER_COMMIT = "5469b5dfd442f1091475fa6600cfd487af878e8f"
BUILDER_SHA256 = "55703ff2354613af3b37c92acc3daef4f33e0d3b7bbc66ede2858a5fd5a03197"
BUILDER_URL = f"https://codeload.github.com/danjboyd/gnustep-cli-new/tar.gz/{BUILDER_COMMIT}"
PROVENANCE = "gnustep-toolchain-provenance.json"
SELECTOR = ".arlen-runtime"


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for data in iter(lambda: f.read(1024 * 1024), b""):
            h.update(data)
    return h.hexdigest()


def target():
    release = platform.freedesktop_os_release()
    arch = {"x86_64": "amd64", "aarch64": "arm64"}.get(platform.machine())
    name = f"{release.get('ID')}-{release.get('VERSION_ID')}-{arch}"
    if name not in ("debian-13-amd64", "debian-13-arm64", "ubuntu-24.04-arm64", "ubuntu-26.04-amd64"):
        raise ValueError("supported native runtime targets: Debian 13 amd64/arm64, Ubuntu 24.04 arm64, Ubuntu 26.04 amd64")
    return name


def lock_for_host():
    return ROOT / "tools/runtime" / (target() + ".lock.json")


def inside(prefix, relative):
    p = prefix / relative
    if not p.resolve().is_relative_to(prefix):
        raise ValueError(f"runtime file escapes its prefix: {relative}")
    return p


def validate(prefix, full=False):
    prefix = Path(prefix).expanduser().resolve(strict=True)
    expected = json.loads(lock_for_host().read_text())
    prov = json.loads((prefix / PROVENANCE).read_text())
    if prov.get("prefix") != str(prefix):
        raise ValueError("runtime has moved; rebuild at its final prefix")
    host = prov.get("build_host", {})
    if host.get("os_version") != target().rsplit("-", 1)[0] or host.get("machine") != platform.machine():
        raise ValueError("runtime was built for another distribution or architecture")
    # Compare the actual pinned components, including flags and patch digests.
    # The original validated Debian lock can have a different filename.
    actual = prov.get("components", [])
    if len(actual) != len(expected["components"]):
        raise ValueError("runtime component list does not match Arlen")
    for want, got in zip(expected["components"], actual):
        for key in ("name", "url", "revision", "configure_args"):
            if want.get(key) != got.get(key):
                raise ValueError(f"runtime {want['name']} {key} does not match Arlen")
        if got.get("resolved_commit") != want["revision"] or got.get("applied_patches") != want["patches"]:
            raise ValueError(f"runtime {want['name']} patch/pin mismatch")
    copied = inside(prefix, prov["lock"]["copy"])
    if digest(copied) != prov["lock"]["sha256"]:
        raise ValueError("runtime lock checksum mismatch")
    copied_lock = json.loads(copied.read_text())
    if copied_lock.get("components") != expected["components"]:
        raise ValueError("installed runtime lock component mismatch")
    for component in expected["components"]:
        for patch in component["patches"]:
            if digest(inside(copied.parent, patch["path"])) != patch["sha256"]:
                raise ValueError("installed runtime patch checksum mismatch")
    for relative in ("System/Library/Makefiles/GNUstep.sh", "System/Tools/gnustep-config",
                     "include/objc/runtime.h", "include/dispatch/dispatch.h",
                     "Local/Library/Headers/Foundation/Foundation.h",
                     "Local/Library/Libraries/libgnustep-base.so", "lib/libobjc.so", "lib/libdispatch.so"):
        if not inside(prefix, relative).is_file():
            raise ValueError(f"incomplete runtime: {relative}")
    files = prov.get("elf_files", {})
    if not files or not any(p.startswith("lib/libobjc.so") for p in files) or not any("libgnustep-base.so" in p for p in files):
        raise ValueError("runtime lacks ELF provenance")
    if full:
        for relative, entry in files.items():
            if digest(inside(prefix, relative)) != entry["sha256"]:
                raise ValueError(f"runtime ELF checksum mismatch: {relative}")
    return prefix


def selected_prefix():
    if os.environ.get("ARLEN_RUNTIME_PREFIX"):
        return Path(os.environ["ARLEN_RUNTIME_PREFIX"])
    marker = ROOT / SELECTOR
    if marker.exists():
        text = marker.read_text().strip()
        if not text or not Path(text).is_absolute():
            raise ValueError("invalid .arlen-runtime selector; expected one absolute prefix")
        return Path(text)
    return None


def select(prefix, framework):
    prefix = validate(prefix, full=True)
    dest = Path(framework).resolve() / SELECTOR
    fd, temporary = tempfile.mkstemp(prefix=SELECTOR + ".", dir=dest.parent)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(str(prefix) + "\n")
        os.replace(temporary, dest)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return prefix


def builder(work):
    archive = work / "builder.tar.gz"
    with urllib.request.urlopen(BUILDER_URL, timeout=60) as response, archive.open("wb") as out:
        shutil.copyfileobj(response, out)
    if digest(archive) != BUILDER_SHA256:
        raise ValueError("pinned runtime builder archive checksum mismatch")
    dest = work / "builder"
    dest.mkdir()
    with tarfile.open(archive) as tar:
        tar.extractall(dest, filter="data")
    return dest / ("gnustep-cli-new-" + BUILDER_COMMIT)


def patch_source(component, patch):
    # Existing race patches remain single-source in CI. Only the Ubuntu lock
    # declares the separately pinned clang 21 source-compatibility patch.
    canonical = f"patches/{component['name']}/{component['name']}.patch"
    if patch["path"] == canonical:
        return ROOT / "tools/ci/tsan-toolchain" / (component["name"] + ".patch")
    if component["name"] == "libdispatch" and patch["path"] == "patches/libdispatch/libdispatch-clang21.patch":
        return ROOT / "tools/runtime/patches/libdispatch-clang21.patch"
    raise ValueError(f"unsupported runtime patch path: {patch['path']}")


def stage_lock(work):
    original = lock_for_host()
    dest = work / "lock" / original.name
    dest.parent.mkdir()
    shutil.copy2(original, dest)
    for component in json.loads(dest.read_text())["components"]:
        for patch in component["patches"]:
            source = patch_source(component, patch)
            if digest(source) != patch["sha256"]:
                raise ValueError(f"repository patch checksum mismatch: {source}")
            copy = dest.parent / patch["path"]
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, copy)
    return dest


def build(runtime_root, jobs):
    root = Path(runtime_root).expanduser().resolve()
    # Immutable final prefix; GNUstep embeds it. Whitespace cannot be expressed
    # reliably by gnustep-config's shell flags. Keep the framework elsewhere.
    if any(c.isspace() for c in str(root)):
        raise ValueError("runtime root must have no whitespace; set ARLEN_RUNTIME_ROOT to an absolute path without spaces")
    managed = [Path("/usr"), Path("/opt/gnustep-cli"), Path.home() / ".local/share/gnustep-cli",
               Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "gnustep-cli"]
    for m in managed:
        m = m.resolve()
        if root == m or root.is_relative_to(m) or m.is_relative_to(root):
            raise ValueError(f"runtime root overlaps a system/managed path: {m}")
    root.mkdir(parents=True, exist_ok=True)
    identity = target() + "-" + digest(lock_for_host())[:16]
    prefix = root / identity
    with (root / ("." + identity + ".lock")).open("a") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        if prefix.exists():
            # Never let the builder remove an existing prefix. Invalid/partial
            # attempts are preserved for diagnosis and require explicit repair.
            return validate(prefix, full=True)
        work = Path(tempfile.mkdtemp(prefix="." + identity + "-build-", dir=root))
        lock = stage_lock(work)
        source = builder(work)
        command = [sys.executable, str(source / "scripts/internal/build_infra.py"), "--json",
                   "build-custom-toolchain", "--lock", str(lock), "--prefix", str(prefix),
                   "--work-dir", str(work / "native"), "--jobs", str(jobs)]
        # Ignore ambient toolchain/compiler flags, make parallelism and preload.
        env = {k: v for k, v in os.environ.items() if not k.startswith("GNUSTEP_") and k not in {
            "LD_LIBRARY_PATH", "LD_PRELOAD", "LIBRARY_PATH", "CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH",
            "PKG_CONFIG_PATH", "CPPFLAGS", "CFLAGS", "CXXFLAGS", "OBJCFLAGS", "OBJCXXFLAGS", "LDFLAGS",
            "MAKEFLAGS", "MFLAGS", "GNUMAKEFLAGS", "CC", "CXX", "OBJC", "OBJCXX"}}
        env["PATH"] = "/usr/bin:/bin"
        print(f"Arlen: building native patched runtime at {prefix}; logs: {work}", file=sys.stderr, flush=True)
        with (work / "builder-result.log").open("w") as log:
            result = subprocess.run(command, cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise ValueError(f"runtime build failed; prior installations preserved; inspect {work}/builder-result.log and {work}/native/logs")
        validate(prefix, full=True)
        (prefix / "arlen-runtime-delivery.json").write_text(json.dumps({
            "builder_commit": BUILDER_COMMIT, "builder_archive_sha256": BUILDER_SHA256,
            "lock_sha256": digest(lock), "target": target(), "prefix": str(prefix), "work": str(work)
        }, indent=2) + "\n")
        return prefix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("build", help="download pinned builder/sources and build at final prefix")
    p.add_argument("--runtime-root", default=os.environ.get("ARLEN_RUNTIME_ROOT", str(Path.home() / ".local/share/arlen/runtimes")))
    p.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 4))
    p.add_argument("--select-for", type=Path, default=ROOT)
    for name in ("check", "select"):
        p = sub.add_parser(name)
        p.add_argument("--prefix", type=Path)
        if name == "select":
            p.add_argument("--select-for", type=Path, default=ROOT)
        else:
            p.add_argument("--full", action="store_true")
    sub.add_parser("selected", help="print configured prefix, without installing anything")
    sub.add_parser("target")
    args = parser.parse_args()
    try:
        if args.command == "target":
            print(target())
        elif args.command == "selected":
            prefix = selected_prefix()
            if prefix:
                print(prefix)
        elif args.command == "build":
            if args.jobs < 1:
                raise ValueError("--jobs must be positive")
            print(select(build(args.runtime_root, args.jobs), args.select_for))
        else:
            prefix = args.prefix or selected_prefix()
            if prefix is None and os.environ.get("GNUSTEP_SH"):
                prefix = Path(os.environ["GNUSTEP_SH"]).resolve().parents[3]
            if prefix is None:
                raise ValueError("no patched runtime selected; run python3 tools/setup_runtime.py build, or select --prefix /final/patched/prefix")
            print(select(prefix, args.select_for) if args.command == "select" else validate(prefix, args.full))
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        print(f"Arlen patched runtime: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
