#!/usr/bin/env python3
"""Generate Phase 33 confidence artifacts from stream seam focused logs."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase33-confidence-v1"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> Dict[str, Any]:
    payload = json.loads(read_text(path))
    if not isinstance(payload, dict):
      raise ValueError(f"expected object JSON at {path}")
    return payload


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 33 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase33")
    parser.add_argument("--objc-log", required=True)
    parser.add_argument("--ts-generated-manifest", required=True)
    parser.add_argument("--ts-unit-manifest", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    objc_log_path = Path(args.objc_log).resolve()
    ts_generated_manifest_path = Path(args.ts_generated_manifest).resolve()
    ts_unit_manifest_path = Path(args.ts_unit_manifest).resolve()

    objc_log = read_text(objc_log_path)
    ts_generated_manifest = load_json(ts_generated_manifest_path)
    ts_unit_manifest = load_json(ts_unit_manifest_path)

    checks = {
        "objc_phase33a_passed": "Phase33ATests: 6 tests PASSED" in objc_log,
        "objc_phase33eh_passed": "Phase33EHTests: 4 tests PASSED" in objc_log,
        "objc_known_runner_limitation_recorded": "xctest" in objc_log and "Running Unit Tests" in objc_log,
        "ts_generated_manifest_passed": ts_generated_manifest.get("status") == "pass",
        "ts_unit_manifest_passed": ts_unit_manifest.get("status") == "pass",
    }
    overall_status = "pass" if all(checks.values()) else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "checks": checks,
        "artifacts": [
            objc_log_path.name,
            ts_generated_manifest_path.name,
            ts_unit_manifest_path.name,
        ],
    }
    write_json(output_dir / "phase33_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 33 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Focused checks:",
            f"- Objective-C `33A-33D` coverage markers present: `{checks['objc_phase33a_passed']}`",
            f"- Objective-C `33E-33H` coverage markers present: `{checks['objc_phase33eh_passed']}`",
            f"- known Debian `xctest` broad-run limitation captured in log: `{checks['objc_known_runner_limitation_recorded']}`",
            f"- TypeScript generated snapshot/typecheck manifest passed: `{checks['ts_generated_manifest_passed']}`",
            f"- TypeScript consumer unit manifest passed: `{checks['ts_unit_manifest_passed']}`",
            "",
            "Focused entrypoint:",
            "",
            "- `make phase33-confidence`",
            "",
        ]
    )
    (output_dir / "phase33_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase33_confidence_eval.json",
            "phase33_confidence.md",
            objc_log_path.name,
            ts_generated_manifest_path.name,
            ts_unit_manifest_path.name,
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase33-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
