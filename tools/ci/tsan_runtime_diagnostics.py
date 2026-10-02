#!/usr/bin/env python3
"""Retain unsuppressed GNUstep reproducers and verify TSAN's positive control."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def run(command, env, timeout=60):
    try:
        result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
        return result.returncode, result.stdout
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or b""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        return 124, output + "\nTSAN probe timed out\n"


def classify_run(mode, suppressed, rc, log):
    complete = f"probe-complete:{mode}" in log
    detected = "ThreadSanitizer: data race" in log and "ALNTSANCanaryCounter" in log
    valid = complete and rc in (0, 66)
    if mode == "canary":
        valid = valid and rc == 66 and detected
    elif suppressed:
        valid = valid and rc == 0 and "WARNING: ThreadSanitizer" not in log
    return {"mode": mode, "suppressed": suppressed, "exit_code": rc,
            "complete": complete, "canary_detected": detected,
            "warnings": log.count("WARNING: ThreadSanitizer"), "valid": valid}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--suppressions", type=Path,
                        default=ROOT / "tests/fixtures/sanitizers/phase9h_tsan.supp")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.pop("LD_PRELOAD", None)
    env.pop("XCTEST_LD_PRELOAD", None)
    binary = output / "tsan-runtime-probe"
    flags = shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
    libs = shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
    command = ["clang", *flags, "-Wno-nullability-completeness", "-fsanitize=thread",
               "-fno-omit-frame-pointer", "-g", str(ROOT / "tests/fixtures/sanitizers/tsan_runtime_probe.m"),
               "-o", str(binary), *libs]
    rc, log = run(command, env)
    (output / "build.log").write_text(log)
    metadata = {}
    for name, cmd in (("compiler", ["clang", "--version"]),
                      ("libraries", ["ldd", str(binary)]),
                      ("kernel", ["uname", "-a"])):
        _, metadata[name] = run(cmd, env)
    metadata["compile_command"] = command
    metadata["suppressions"] = args.suppressions.read_text()
    (output / "toolchain.json").write_text(json.dumps(metadata, indent=2) + "\n")
    records = []
    summary = {"status": "fail", "build_exit_code": rc, "runs": records}
    if rc == 0:
        for suppressed in (False, True):
            for mode in ("startup", "monitor", "lock", "queue", "canary"):
                options = "halt_on_error=0:exitcode=66:second_deadlock_stack=1"
                if suppressed:
                    options += f":suppressions={args.suppressions.resolve()}"
                env["TSAN_OPTIONS"] = options
                rc, log = run([str(binary), mode], env)
                name = f"{'suppressed' if suppressed else 'raw'}-{mode}.log"
                (output / name).write_text(log)
                record = classify_run(mode, suppressed, rc, log)
                record["log"] = name
                records.append(record)
        summary["status"] = "pass" if all(r["valid"] for r in records) else "fail"
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"tsan-runtime-diagnostics: {summary['status']} ({output})")
    return 0 if summary["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
