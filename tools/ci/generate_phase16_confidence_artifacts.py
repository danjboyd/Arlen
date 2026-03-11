#!/usr/bin/env python3
"""Generate Phase 16 confidence artifacts from unit and focused integration logs."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase16-confidence-v1"
UNIT_REQUIRED_MARKERS = {
    "phase16a_suite": "XCTest:   Running Phase16ATests",
    "phase16a_jobs_metadata": "testMetadataAndOperatorStatePersistAcrossReconfigure",
    "phase16b_suite": "XCTest:   Running Phase16BTests",
    "phase16b_notifications_durability": "testNotificationStatePersistsAcrossReconfigure",
    "phase16c_suite": "XCTest:   Running Phase16CTests",
    "phase16c_storage_variants": "testVariantGenerationUsesTransformHookAndPersistsActivity",
    "phase16d_suite": "XCTest:   Running Phase16DTests",
    "phase16d_incremental_sync": "testFullReindexAndIncrementalSyncShareJobContractAndPersistGenerationState",
    "phase16e_suite": "XCTest:   Running Phase16ETests",
    "phase16e_ops_drilldown": "testHistoryAndCardWidgetsPersistAcrossReconfigure",
    "phase16f_suite": "XCTest:   Running Phase16FTests",
    "phase16f_admin_productivity": "testListMetadataBulkExportAndAutocompleteContracts",
}
INTEGRATION_REQUIRED_MARKERS = {
    "phase16_integration_suite": "XCTest:   Running Phase16ModuleIntegrationTests",
    "phase16_routes_contract": "testPhase16AdminSearchAndOpsRoutesExposeMaturedContracts",
}


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


def parse_log(path: Path, required_markers: Dict[str, str]) -> Dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    missing = [name for name, marker in required_markers.items() if marker not in text]
    passed = "FAILED" not in text and "PASSED" in text and not missing
    summary_line = ""
    for line in reversed(text.splitlines()):
      if "XCTest:" in line and ("PASSED" in line or "FAILED" in line):
        summary_line = line.strip()
        break
    return {
        "status": "passed" if passed else "failed",
        "summary": summary_line,
        "required_markers": required_markers,
        "missing_markers": missing,
        "log": path.name,
    }


def render_markdown(unit_summary: Dict[str, Any], integration_summary: Dict[str, Any], overall_status: str) -> str:
    lines = [
        "# Phase 16 Confidence",
        "",
        f"- status: `{overall_status}`",
        f"- unit suite: `{unit_summary['status']}`",
        f"- focused modules integration: `{integration_summary['status']}`",
        "",
        "## Unit Coverage",
        "",
        f"- summary: `{unit_summary['summary'] or 'missing summary'}`",
    ]
    for marker_name in unit_summary.get("missing_markers", []):
        lines.append(f"- missing marker: `{marker_name}`")
    lines.extend(
        [
            "",
            "## Focused Integration Coverage",
            "",
            f"- summary: `{integration_summary['summary'] or 'missing summary'}`",
        ]
    )
    for marker_name in integration_summary.get("missing_markers", []):
        lines.append(f"- missing marker: `{marker_name}`")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 16 confidence artifacts")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase16")
    parser.add_argument("--unit-log", required=True)
    parser.add_argument("--integration-log", required=True)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    unit_summary = parse_log(Path(args.unit_log), UNIT_REQUIRED_MARKERS)
    integration_summary = parse_log(Path(args.integration_log), INTEGRATION_REQUIRED_MARKERS)
    overall_status = (
        "passed"
        if unit_summary["status"] == "passed" and integration_summary["status"] == "passed"
        else "failed"
    )

    eval_payload = {
        "version": VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "git_commit": git_commit(repo_root),
        "status": overall_status,
        "unit_suite": unit_summary,
        "focused_integration": integration_summary,
    }
    write_json(output_dir / "phase16_confidence_eval.json", eval_payload)
    (output_dir / "phase16_confidence.md").write_text(
        render_markdown(unit_summary, integration_summary, overall_status),
        encoding="utf-8",
    )
    write_json(
        output_dir / "manifest.json",
        {
            "version": VERSION,
            "generated_at": eval_payload["generated_at"],
            "git_commit": eval_payload["git_commit"],
            "status": overall_status,
            "artifacts": [
                "phase16_confidence_eval.json",
                "phase16_confidence.md",
                Path(args.unit_log).name,
                Path(args.integration_log).name,
            ],
        },
    )
    print(f"phase16-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
