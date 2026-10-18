#!/usr/bin/env python3
"""Summarize ASan/UBSan log_path reports for the nightly integration lane.

Each report is classified:
- arlen: a frame or the reporting module is in the repository (sources,
  build/ artifacts, test bundles). These fail the lane.
- tool: no Arlen frame, and the report comes from a /usr/bin program that
  inherited the preloaded runtime (make's strndup, dd's aligned_alloc).
  These are recorded but don't fail the lane.
- unattributed: anything else. These fail the lane too, so a report is never
  dropped silently.
"""
import argparse
import json
import os
import re
import sys

FRAME = re.compile(r"^\s*#\d+\s+0x[0-9a-f]+\s+(?:in\s+(\S+)\s*)?(.*)$")
SUMMARY = re.compile(r"^SUMMARY: (\S+): (.*)$")
# Vendored tools-xctest per-class summaries:
#   "XCTest:   Cls: 48 tests PASSED", "... 0 tests PASSED, 1 skipped",
#   "XCTest:   Cls: 2/7 tests FAILED", "... 2/7 tests FAILED (1 tests skipped)".
CLASS_PASSED = re.compile(r"XCTest:\s+\w+: (\d+) tests? PASSED(?:, (\d+) skipped)?")
CLASS_FAILED = re.compile(r"XCTest:\s+\w+: (\d+)/(\d+) tests? FAILED(?: \((\d+) tests? skipped\))?")
ARLEN_MODULES = ("ArlenIntegrationTests", "ArlenUnitTests", "libArlenFramework", "boomhauer", "eocc")


def classify(text, repo_root):
    frames = []
    for line in text.splitlines():
        match = FRAME.match(line)
        if match:
            frames.append(line.strip())
    arlen = any(repo_root in f or any(m in f for m in ARLEN_MODULES) for f in frames)
    if arlen or (repo_root in text and not frames):
        return "arlen", frames
    if any("/usr/bin/" in f for f in frames) or re.search(r"\(/usr/bin/[^)+]+\+0x", text):
        return "tool", frames
    return "unattributed", frames


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--reports-dir", required=True)
    parser.add_argument("--test-log", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    repo_root = os.path.realpath(args.repo_root)
    reports = []
    if os.path.isdir(args.reports_dir):
        for name in sorted(os.listdir(args.reports_dir)):
            path = os.path.join(args.reports_dir, name)
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
            if not text.strip():
                continue
            kind, frames = classify(text, repo_root)
            summary = next((m.group(2) for m in map(SUMMARY.match, text.splitlines()) if m), "")
            reports.append({"file": name, "kind": kind, "summary": summary, "top_frames": frames[:6]})

    results = {}
    if os.path.isfile(args.test_log):
        with open(args.test_log, encoding="utf-8", errors="replace") as handle:
            log = handle.read()
        passed = failed = skipped = 0
        for count, skip in CLASS_PASSED.findall(log):
            passed += int(count)
            skipped += int(skip or 0)
        for fails, total, skip in CLASS_FAILED.findall(log):
            failed += int(fails)
            passed += int(total) - int(fails)
            skipped += int(skip or 0)
        results = {"passed": passed, "failed": failed, "skipped": skipped}

    counts = {kind: sum(1 for r in reports if r["kind"] == kind) for kind in ("arlen", "tool", "unattributed")}
    payload = {"version": "integration-sanitizers-nightly-v1", "tests": results, "report_counts": counts,
               "reports": reports}
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")

    print(f"integration sanitizers: tests {results or 'unknown'}; reports {counts}")
    for report in reports:
        if report["kind"] != "tool":
            print(f"integration sanitizers: {report['kind']} report {report['file']}: {report['summary']}", file=sys.stderr)
            for frame in report["top_frames"]:
                print(f"    {frame}", file=sys.stderr)
    return 1 if counts["arlen"] or counts["unattributed"] else 0


if __name__ == "__main__":
    sys.exit(main())
