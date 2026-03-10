#!/usr/bin/env python3
"""Generate Phase 15 confidence artifacts from unit and focused auth UI logs."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase15-confidence-v1"
UNIT_REQUIRED_MARKERS = {
    "phase13e_suite": "XCTest:   Running Phase13ETests",
    "auth_ui_generated_paths": "testAuthUIConfigurationResolvesGeneratedPathsAndContextHooks",
    "auth_ui_headless_routes": "testHeadlessModeDoesNotRegisterInteractiveHTMLRoutes",
    "auth_ui_eject": "testModuleEjectAuthUIScaffoldsGeneratedTemplatesAndConfig",
}
INTEGRATION_REQUIRED_MARKERS = {
    "phase13_auth_admin_suite": "XCTest:   Running Phase13AuthAdminIntegrationTests",
    "headless_http_mode_split": "testAuthModuleHeadlessModeKeepsAPIAndProviderRoutesWhileSuppressingHTMLPages",
    "module_ui_layout_and_partials": "testAuthModuleModuleUIUsesAppLayoutHookAndPartialOverrides",
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


def render_markdown(
    unit_summary: Dict[str, Any],
    integration_summary: Dict[str, Any],
    overall_status: str,
    reason: str = "",
) -> str:
    lines = [
        "# Phase 15 Confidence",
        "",
        f"- status: `{overall_status}`",
    ]
    if reason:
        lines.append(f"- reason: `{reason}`")
    lines.extend(
        [
            f"- unit suite: `{unit_summary['status']}`",
            f"- focused auth UI bundle: `{integration_summary['status']}`",
            "",
            "## Unit Coverage",
            "",
            f"- summary: `{unit_summary['summary'] or 'missing summary'}`",
        ]
    )
    for marker_name in unit_summary.get("missing_markers", []):
        lines.append(f"- missing marker: `{marker_name}`")
    lines.extend(
        [
            "",
            "## Focused Auth UI Coverage",
            "",
            f"- summary: `{integration_summary['summary'] or 'missing summary'}`",
        ]
    )
    for marker_name in integration_summary.get("missing_markers", []):
        lines.append(f"- missing marker: `{marker_name}`")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 15 confidence artifacts")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase15")
    parser.add_argument("--unit-log", required=True)
    parser.add_argument("--integration-log", required=True)
    parser.add_argument("--mode", choices=["run", "skipped"], default="run")
    parser.add_argument("--reason", default="")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    unit_summary = parse_log(Path(args.unit_log), UNIT_REQUIRED_MARKERS)
    integration_summary = parse_log(Path(args.integration_log), INTEGRATION_REQUIRED_MARKERS)

    if args.mode == "skipped":
        eval_payload = {
            "version": VERSION,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "git_commit": git_commit(repo_root),
            "status": "skipped",
            "reason": args.reason,
            "unit_suite": unit_summary,
            "focused_integration": integration_summary,
        }
        write_json(output_dir / "phase15_confidence_eval.json", eval_payload)
        (output_dir / "phase15_confidence.md").write_text(
            render_markdown(unit_summary, integration_summary, "skipped", args.reason),
            encoding="utf-8",
        )
        write_json(
            output_dir / "manifest.json",
            {
                "version": VERSION,
                "generated_at": eval_payload["generated_at"],
                "git_commit": eval_payload["git_commit"],
                "status": "skipped",
                "artifacts": [
                    "phase15_confidence_eval.json",
                    "phase15_confidence.md",
                    Path(args.unit_log).name,
                    Path(args.integration_log).name,
                ],
            },
        )
        print(f"phase15-confidence: generated skipped artifacts in {output_dir}")
        return 0

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
    write_json(output_dir / "phase15_confidence_eval.json", eval_payload)
    (output_dir / "phase15_confidence.md").write_text(
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
                "phase15_confidence_eval.json",
                "phase15_confidence.md",
                Path(args.unit_log).name,
                Path(args.integration_log).name,
            ],
        },
    )
    print(f"phase15-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
