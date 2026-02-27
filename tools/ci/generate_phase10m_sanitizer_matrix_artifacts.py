#!/usr/bin/env python3
"""Generate Phase 10M sanitizer matrix confidence artifacts."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List


VERSION = "phase10m-sanitizer-matrix-v1"


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


def git_commit(repo_root: Path) -> str:
    try:
        return (
            subprocess.check_output(
                ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
                stderr=subprocess.DEVNULL,
                text=True,
            )
            .strip()
        )
    except Exception:
        return "unknown"


def make_markdown(payload: Dict[str, Any], output_dir: Path) -> str:
    lines: List[str] = []
    lines.append("# Phase 10M Sanitizer Matrix")
    lines.append("")
    lines.append(f"Generated at: `{payload['generated_at']}`")
    lines.append(f"Git commit: `{payload['commit']}`")
    lines.append("")
    lines.append("| Lane | Blocking | Status | Evidence |")
    lines.append("| --- | --- | --- | --- |")
    for lane in payload.get("lane_results", []):
        lines.append(
            "| {id} | {blocking} | {status} | {evidence} |".format(
                id=lane.get("id", ""),
                blocking="yes" if lane.get("blocking", False) else "no",
                status=lane.get("status", "unknown"),
                evidence=lane.get("evidence", ""),
            )
        )

    lines.append("")
    lines.append("## Violations")
    lines.append("")
    violations = payload.get("violations", [])
    if isinstance(violations, list) and violations:
        for violation in violations:
            lines.append(f"- {violation}")
    else:
        lines.append("- none")

    summary = payload.get("summary", {})
    lines.append("")
    lines.append("## Totals")
    lines.append("")
    lines.append(f"- Total lanes: `{summary.get('total', 0)}`")
    lines.append(f"- Passed: `{summary.get('passed', 0)}`")
    lines.append(f"- Failed: `{summary.get('failed', 0)}`")
    lines.append(f"- Skipped: `{summary.get('skipped', 0)}`")
    lines.append(f"- Blocking failures: `{summary.get('blocking_failures', 0)}`")
    lines.append(f"- Status: `{summary.get('status', 'fail')}`")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 10M sanitizer matrix artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--fixture", default="tests/fixtures/sanitizers/phase10m_sanitizer_matrix.json")
    parser.add_argument("--lane-results", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase10m/sanitizers")
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    fixture = (repo_root / args.fixture).resolve()
    lane_results_path = Path(args.lane_results).resolve()
    output_dir = Path(args.output_dir).resolve()

    matrix = load_json(fixture)
    if matrix.get("version") != VERSION:
        raise SystemExit("phase10m sanitizer matrix fixture version mismatch")

    lane_payload = load_json(lane_results_path)
    raw_results = lane_payload.get("lane_results")
    if not isinstance(raw_results, list):
        raw_results = []

    required = matrix.get("lanes", [])
    if not isinstance(required, list):
        required = []
    required_map = {
        str(entry.get("id", "")): bool(entry.get("blocking", False))
        for entry in required
        if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    }

    observed_map: Dict[str, Dict[str, Any]] = {}
    for lane in raw_results:
        if not isinstance(lane, dict):
            continue
        lane_id = lane.get("id")
        if not isinstance(lane_id, str) or lane_id == "":
            continue
        observed_map[lane_id] = lane

    violations: List[str] = []
    lane_results: List[Dict[str, Any]] = []
    for lane_id, blocking in required_map.items():
        observed = observed_map.get(lane_id)
        if observed is None:
            lane_results.append(
                {
                    "id": lane_id,
                    "blocking": blocking,
                    "status": "missing",
                    "evidence": "",
                }
            )
            violations.append(f"missing required lane result: {lane_id}")
            continue
        status = str(observed.get("status", "unknown"))
        evidence = str(observed.get("evidence", ""))
        lane_results.append(
            {
                "id": lane_id,
                "blocking": blocking,
                "status": status,
                "evidence": evidence,
                "return_code": int(observed.get("return_code", 0)),
            }
        )
        if blocking and status != "pass":
            violations.append(f"blocking lane {lane_id} status={status}")

    total = len(lane_results)
    passed = sum(1 for lane in lane_results if lane.get("status") == "pass")
    failed = sum(1 for lane in lane_results if lane.get("status") == "fail")
    skipped = sum(1 for lane in lane_results if lane.get("status") in {"skipped", "missing"})
    blocking_failures = sum(
        1
        for lane in lane_results
        if lane.get("blocking") and lane.get("status") != "pass"
    )

    status = "pass" if blocking_failures == 0 and not violations else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": git_commit(repo_root),
        "fixture_version": matrix.get("version", ""),
        "lane_results": lane_results,
        "violations": violations,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "blocking_failures": blocking_failures,
            "status": status,
        },
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    write_json(output_dir / "sanitizer_lane_status.json", payload)
    write_json(output_dir / "sanitizer_matrix_summary.json", payload)
    markdown = make_markdown(payload, output_dir)
    (output_dir / "phase10m_sanitizer_matrix.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": payload["commit"],
        "status": status,
        "artifacts": [
            "sanitizer_lane_status.json",
            "sanitizer_matrix_summary.json",
            "phase10m_sanitizer_matrix.md",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase10m-sanitizer-matrix: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
