#!/usr/bin/env python3
"""Native concurrency controls against the selected normal (uninstrumented) runtime.

These exercise patched paths on the actual CPU; they do not substitute for the
separate instrumented TSan acceptance gate.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[2]
MODES = ("startup", "monitor", "lock", "queue", "queue-idle", "serial-queue", "foundation",
         "dispatch", "semaphore", "group", "group-notify", "task-signal", "kvc", "buffer")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    subprocess.run(["python3", str(ROOT / "tools/setup_runtime.py"), "check", "--full"], check=True)
    flags = shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
    libs = shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
    command = ["clang", *flags, "-Wno-nullability-completeness", "-O2", "-g", "-fno-omit-frame-pointer",
               str(ROOT / "tests/fixtures/sanitizers/tsan_runtime_probe.m"), "-o", str(out / "normal-probe"), *libs, "-ldispatch"]
    result = subprocess.run(command, capture_output=True, text=True)
    (out / "build.log").write_text(result.stdout + result.stderr)
    result.check_returncode()
    records = []
    for mode in MODES:
        result = subprocess.run([str(out / "normal-probe"), mode], capture_output=True, text=True, timeout=120)
        (out / (mode + ".log")).write_text(result.stdout + result.stderr)
        records.append({"mode": mode, "exit_code": result.returncode,
                        "complete": "probe-complete:" + mode in result.stdout + result.stderr})
    metadata = {"command": command, "runtime_prefix": os.environ.get("ARLEN_RUNTIME_PREFIX"), "runs": records}
    for name, command in (("machine", ["uname", "-m"]), ("compiler", ["clang", "--version"]),
                          ("linkage", ["ldd", str(out / "normal-probe")])):
        metadata[name] = subprocess.check_output(command, text=True)
    prefix = Path(os.environ["ARLEN_RUNTIME_PREFIX"]).resolve()
    for library in ("libobjc.so", "libdispatch.so", "libgnustep-base.so", "libBlocksRuntime.so"):
        paths = [line.split("=>", 1)[1].split()[0] for line in metadata["linkage"].splitlines()
                 if line.strip().startswith(library) and "=>" in line]
        if not paths or not all(Path(p).resolve().is_relative_to(prefix) for p in paths):
            raise RuntimeError(f"native probe loaded {library} outside selected prefix: {paths}")
    icu_flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "icu-i18n", "icu-uc"], text=True))
    icu_command = ["clang", *flags, "-O2", "-g", str(ROOT / "tests/fixtures/runtime/icu_runtime_contract.m"),
                   "-o", str(out / "icu-runtime-contract"), *libs, *icu_flags]
    result = subprocess.run(icu_command, capture_output=True, text=True)
    (out / "icu-build.log").write_text(result.stdout + result.stderr)
    metadata["icu_compile_command"] = icu_command
    metadata["icu_build_exit_code"] = result.returncode
    if result.returncode == 0:
        result = subprocess.run([str(out / "icu-runtime-contract")], capture_output=True, text=True, timeout=30)
        (out / "icu-runtime.log").write_text(result.stdout + result.stderr)
        metadata["icu_exit_code"] = result.returncode
        metadata["icu_output"] = result.stdout + result.stderr
    metadata["icu_valid"] = (metadata.get("icu_exit_code") == 0 and
                             "pass:ICU-and-Foundation-timezone-formatting" in metadata.get("icu_output", ""))
    metadata["status"] = "pass" if metadata["icu_valid"] and all(r["exit_code"] == 0 and r["complete"] for r in records) else "fail"
    (out / "summary.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"native normal runtime controls: {metadata['status']} ({len(records)} modes, ICU date contract)")
    return 0 if metadata["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
