#!/usr/bin/env python3
"""Generate Phase 30 confidence artifacts for the Apple-runtime baseline."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List


VERSION = "phase30-confidence-v1"


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"expected object JSON at {path}")
    return payload


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def find_check(payload: Dict[str, Any], check_id: str) -> Dict[str, Any]:
    for entry in payload.get("checks", []):
        if isinstance(entry, dict) and entry.get("id") == check_id:
            return entry
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 30 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase30")
    parser.add_argument("--doctor", required=True)
    parser.add_argument("--toolchain", required=True)
    parser.add_argument("--build-log", required=True)
    parser.add_argument("--xctest-log", required=True)
    parser.add_argument("--runtime-log", required=True)
    parser.add_argument("--repo-root", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    repo_root = Path(args.repo_root).resolve()
    doctor = load_json(Path(args.doctor).resolve())
    toolchain = load_json(Path(args.toolchain).resolve())
    build_log = text(Path(args.build_log).resolve())
    xctest_log = text(Path(args.xctest_log).resolve())
    runtime_log = text(Path(args.runtime_log).resolve())

    expected_artifacts: List[str] = [
        "build/apple/eocc",
        "build/apple/lib/libArlenFramework.a",
        "build/apple/arlen",
        "build/apple/apple-auth-audit",
        "build/apple/boomhauer",
    ]

    checks = {
        "doctor_no_failures": doctor.get("summary", {}).get("fail") == 0,
        "doctor_xctest_visible": find_check(doctor, "tool_xctest").get("status") == "pass",
        "toolchain_uses_full_xcode": "/Applications/Xcode.app/Contents/Developer"
        in str(toolchain.get("active_developer_dir", "")),
        "toolchain_resolves_xctest": str(toolchain.get("xctest_path", "")).endswith("/usr/bin/xctest"),
        "build_log_reports_artifacts": "build-apple: built artifacts:" in build_log,
        "xctest_smoke_passed": "apple-xctest-smoke: passed" in xctest_log
        and "0 failures" in xctest_log,
        "runtime_smoke_passed": "test-apple: Apple runtime verification passed" in runtime_log,
        "runtime_smoke_exercised_xctest": "test-apple: running Apple XCTest smoke" in runtime_log,
        "runtime_smoke_exercised_auth_example": "test-apple: starting auth_primitives example on port"
        in runtime_log,
        "build_artifacts_present": all((repo_root / rel).exists() for rel in expected_artifacts),
    }

    overall_status = "pass" if all(checks.values()) else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "checks": checks,
        "doctor_summary": doctor.get("summary", {}),
        "toolchain": toolchain,
        "expected_artifacts": expected_artifacts,
        "artifacts": [
            Path(args.doctor).name,
            Path(args.toolchain).name,
            Path(args.build_log).name,
            Path(args.xctest_log).name,
            Path(args.runtime_log).name,
        ],
    }
    write_json(output_dir / "phase30_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 30 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Apple baseline checks:",
            f"- doctor reported zero failures: `{checks['doctor_no_failures']}`",
            f"- doctor resolved Apple XCTest: `{checks['doctor_xctest_visible']}`",
            f"- active developer dir is full Xcode: `{checks['toolchain_uses_full_xcode']}`",
            f"- `xcrun --find xctest` resolves: `{checks['toolchain_resolves_xctest']}`",
            f"- Apple XCTest smoke passed: `{checks['xctest_smoke_passed']}`",
            f"- Apple build log reported artifacts: `{checks['build_log_reports_artifacts']}`",
            f"- built Apple artifacts are present: `{checks['build_artifacts_present']}`",
            f"- Apple runtime smoke passed: `{checks['runtime_smoke_passed']}`",
            f"- Apple runtime smoke exercised XCTest: `{checks['runtime_smoke_exercised_xctest']}`",
            f"- Apple runtime smoke exercised auth example coverage: `{checks['runtime_smoke_exercised_auth_example']}`",
            "",
            "Focused entrypoints:",
            "",
            "- `bash ./tools/ci/run_phase30_confidence.sh`",
            "- `./bin/test --smoke-only`",
            "",
        ]
    )
    (output_dir / "phase30_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase30_confidence_eval.json",
            "phase30_confidence.md",
            Path(args.doctor).name,
            Path(args.toolchain).name,
            Path(args.build_log).name,
            Path(args.xctest_log).name,
            Path(args.runtime_log).name,
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase30-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
