#!/usr/bin/env python3
"""Generate Phase 9H sanitizer confidence artifacts."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List


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
        output = subprocess.check_output(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return output.strip()
    except Exception:
        return "unknown"



def status_delta(previous: Dict[str, Any], current: Dict[str, str]) -> List[Dict[str, str]]:
    previous_lanes = previous.get("lane_statuses", {})
    if not isinstance(previous_lanes, dict):
        previous_lanes = {}

    deltas: List[Dict[str, str]] = []
    for lane_id, status in sorted(current.items()):
        old = previous_lanes.get(lane_id)
        old_str = old if isinstance(old, str) else "unknown"
        if old_str != status:
            deltas.append(
                {
                    "lane": lane_id,
                    "from": old_str,
                    "to": status,
                }
            )
    return deltas



def build_markdown(
    generated_at: str,
    commit: str,
    matrix: Dict[str, Any],
    lane_statuses: Dict[str, str],
    suppression_summary: Dict[str, Any],
    deltas: List[Dict[str, str]],
    output_dir: Path,
) -> str:
    lines: List[str] = []
    lines.append("# Phase 9H Sanitizer Confidence Summary")
    lines.append("")
    lines.append(f"Generated at: `{generated_at}`")
    lines.append(f"Git commit: `{commit}`")
    lines.append("")
    lines.append("## Lane Status")
    lines.append("")
    lines.append("| Lane | Blocking | Owner | Status | Coverage targets |")
    lines.append("| --- | --- | --- | --- | --- |")
    lanes = matrix.get("lanes", [])
    if not isinstance(lanes, list):
        lanes = []
    for lane in lanes:
        if not isinstance(lane, dict):
            continue
        lane_id = str(lane.get("id", ""))
        status = lane_statuses.get(lane_id, "unknown")
        blocking = "yes" if bool(lane.get("blocking")) else "no"
        owner = str(lane.get("owner", ""))
        targets = lane.get("coverageTargets", [])
        if not isinstance(targets, list):
            targets = []
        coverage = ", ".join(str(item) for item in targets)
        lines.append(f"| {lane_id} | {blocking} | {owner} | {status} | {coverage} |")

    lines.append("")
    lines.append("## Suppression Summary")
    lines.append("")
    lines.append(f"- Active suppressions: `{suppression_summary.get('active_count', 0)}`")
    lines.append(f"- Resolved suppressions: `{suppression_summary.get('resolved_count', 0)}`")
    lines.append(f"- Expiring within 14 days: `{suppression_summary.get('expiring_soon', 0)}`")

    lines.append("")
    lines.append("## Lane Deltas")
    lines.append("")
    if deltas:
        for delta in deltas:
            lines.append(
                f"- `{delta['lane']}`: `{delta['from']}` -> `{delta['to']}`"
            )
    else:
        lines.append("- No lane status deltas from prior artifact.")

    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)



def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 9H sanitizer confidence artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument(
        "--matrix-fixture",
        default="tests/fixtures/sanitizers/phase9h_sanitizer_matrix.json",
    )
    parser.add_argument(
        "--suppressions-fixture",
        default="tests/fixtures/sanitizers/phase9h_suppressions.json",
    )
    parser.add_argument("--output-dir", default="build/release_confidence/phase9h")
    parser.add_argument(
        "--blocking-status",
        choices=["pass", "fail", "skipped"],
        required=True,
    )
    parser.add_argument(
        "--tsan-status",
        choices=["pass", "fail", "skipped"],
        required=True,
    )
    parser.add_argument(
        "--tsan-log-path",
        default="build/sanitizers/tsan/tsan.log",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    matrix_path = (repo_root / args.matrix_fixture).resolve()
    suppressions_path = (repo_root / args.suppressions_fixture).resolve()

    matrix = load_json(matrix_path)
    suppressions = load_json(suppressions_path)

    suppression_entries = suppressions.get("suppressions", [])
    if not isinstance(suppression_entries, list):
        suppression_entries = []

    active_count = 0
    resolved_count = 0
    expiring_soon = 0
    soon_cutoff = date.today() + timedelta(days=14)
    for entry in suppression_entries:
        if not isinstance(entry, dict):
            continue
        status = entry.get("status", "active")
        if status == "resolved":
            resolved_count += 1
            continue
        active_count += 1
        expires_on = entry.get("expiresOn")
        if not isinstance(expires_on, str):
            continue
        try:
            expires_date = date.fromisoformat(expires_on)
        except Exception:
            continue
        if expires_date <= soon_cutoff:
            expiring_soon += 1

    lane_statuses = {
        "asan_ubsan_blocking": args.blocking_status,
        "tsan_experimental": args.tsan_status,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    lane_status_path = output_dir / "sanitizer_lane_status.json"
    previous_payload: Dict[str, Any] = {}
    if lane_status_path.exists():
        try:
            previous_payload = load_json(lane_status_path)
        except Exception:
            previous_payload = {}

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    commit = git_commit(repo_root)

    deltas = status_delta(previous_payload, lane_statuses)
    tsan_log = (repo_root / args.tsan_log_path).resolve()

    lane_status_payload = {
        "version": "phase9h-sanitizer-confidence-v1",
        "generated_at": generated_at,
        "commit": commit,
        "lane_statuses": lane_statuses,
        "deltas": deltas,
    }
    matrix_payload = {
        "version": "phase9h-sanitizer-confidence-v1",
        "generated_at": generated_at,
        "commit": commit,
        "matrix_fixture_version": matrix.get("version", ""),
        "lanes": matrix.get("lanes", []),
    }
    suppression_payload = {
        "version": "phase9h-sanitizer-confidence-v1",
        "generated_at": generated_at,
        "commit": commit,
        "suppression_fixture_version": suppressions.get("version", ""),
        "active_count": active_count,
        "resolved_count": resolved_count,
        "expiring_soon": expiring_soon,
    }

    markdown = build_markdown(
        generated_at,
        commit,
        matrix,
        lane_statuses,
        suppression_payload,
        deltas,
        output_dir,
    )

    write_json(lane_status_path, lane_status_payload)
    write_json(output_dir / "sanitizer_matrix_summary.json", matrix_payload)
    write_json(output_dir / "sanitizer_suppression_summary.json", suppression_payload)
    (output_dir / "phase9h_sanitizer_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": "phase9h-sanitizer-confidence-v1",
        "generated_at": generated_at,
        "commit": commit,
        "artifacts": [
            "sanitizer_lane_status.json",
            "sanitizer_matrix_summary.json",
            "sanitizer_suppression_summary.json",
            "phase9h_sanitizer_confidence.md",
        ],
        "tsan": {
            "status": args.tsan_status,
            "log_path": str(tsan_log),
            "log_exists": tsan_log.exists(),
        },
    }
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase9h-sanitizers: generated artifacts in {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
