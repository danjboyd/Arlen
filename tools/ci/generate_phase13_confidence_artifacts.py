#!/usr/bin/env python3
"""Generate Phase 13 confidence artifacts from unit logs and sample app flows."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase13-confidence-v1"


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object at {path}")
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


def parse_unit_log(path: Path) -> Dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    required_markers = {
        "phase13e_suite": "XCTest:   Running Phase13ETests",
        "phase13h_suite": "XCTest:   Running Phase13HTests",
    }
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


def evaluate_flow(payload: Dict[str, Any]) -> Dict[str, Any]:
    register = payload.get("register") if isinstance(payload.get("register"), dict) else {}
    step_up = payload.get("step_up") if isinstance(payload.get("step_up"), dict) else {}
    resources = payload.get("admin_resources") if isinstance(payload.get("admin_resources"), dict) else {}
    action = payload.get("orders_action") if isinstance(payload.get("orders_action"), dict) else {}
    identifiers = resources.get("identifiers") if isinstance(resources.get("identifiers"), list) else []
    action_status = action.get("body") if isinstance(action.get("body"), dict) else {}

    checks = {
        "register_authenticated": register.get("status") == 200
        and isinstance(register.get("body"), dict)
        and register["body"].get("authenticated") is True,
        "step_up_aal2": step_up.get("status") == 200
        and isinstance(step_up.get("body"), dict)
        and step_up["body"].get("aal") == 2,
        "resource_catalog": resources.get("status") == 200 and "users" in identifiers and "orders" in identifiers,
        "orders_action": action.get("status") == 200
        and action_status.get("result", {}).get("record", {}).get("status") == "reviewed",
    }
    return {
        "status": "passed" if all(checks.values()) else "failed",
        "checks": checks,
        "flow": payload,
    }


def render_markdown(unit_summary: Dict[str, Any], flow_summary: Dict[str, Any], overall_status: str) -> str:
    identifiers = []
    resources = flow_summary.get("flow", {}).get("admin_resources", {})
    if isinstance(resources, dict) and isinstance(resources.get("identifiers"), list):
        identifiers = resources["identifiers"]
    lines = [
        "# Phase 13 Confidence",
        "",
        f"- status: `{overall_status}`",
        f"- unit suite: `{unit_summary['status']}`",
        f"- sample flow: `{flow_summary['status']}`",
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
            "## Sample App Flow",
            "",
            f"- resources: `{', '.join(identifiers)}`",
            f"- register authenticated: `{flow_summary['checks'].get('register_authenticated')}`",
            f"- step-up AAL2: `{flow_summary['checks'].get('step_up_aal2')}`",
            f"- resource catalog: `{flow_summary['checks'].get('resource_catalog')}`",
            f"- orders action: `{flow_summary['checks'].get('orders_action')}`",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 13 confidence artifacts")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase13")
    parser.add_argument("--unit-log", required=True)
    parser.add_argument("--flow")
    parser.add_argument("--mode", choices=["run", "skipped"], default="run")
    parser.add_argument("--reason", default="")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    unit_summary = parse_unit_log(Path(args.unit_log))

    if args.mode == "skipped":
        eval_payload = {
            "version": VERSION,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "git_commit": git_commit(repo_root),
            "status": "skipped",
            "reason": args.reason,
            "unit_suite": unit_summary,
        }
        write_json(output_dir / "phase13_confidence_eval.json", eval_payload)
        (output_dir / "phase13_confidence.md").write_text(
            "\n".join(
                [
                    "# Phase 13 Confidence",
                    "",
                    "- status: `skipped`",
                    f"- reason: `{args.reason or 'not provided'}`",
                    f"- unit suite: `{unit_summary['status']}`",
                    "",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        write_json(
            output_dir / "manifest.json",
            {
                "version": VERSION,
                "generated_at": eval_payload["generated_at"],
                "git_commit": eval_payload["git_commit"],
                "status": "skipped",
                "artifacts": ["phase13_confidence_eval.json", "phase13_confidence.md", Path(args.unit_log).name],
            },
        )
        print(f"phase13-confidence: generated skipped artifacts in {output_dir}")
        return 0

    if not args.flow:
        raise SystemExit("--flow is required when --mode=run")

    flow_summary = evaluate_flow(load_json(Path(args.flow)))
    overall_status = (
        "passed" if unit_summary["status"] == "passed" and flow_summary["status"] == "passed" else "failed"
    )
    eval_payload = {
        "version": VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "git_commit": git_commit(repo_root),
        "status": overall_status,
        "unit_suite": unit_summary,
        "sample_app_flow": flow_summary,
    }
    write_json(output_dir / "phase13_confidence_eval.json", eval_payload)
    (output_dir / "phase13_confidence.md").write_text(
        render_markdown(unit_summary, flow_summary, overall_status),
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
                "phase13_confidence_eval.json",
                "phase13_confidence.md",
                Path(args.unit_log).name,
                Path(args.flow).name,
            ],
        },
    )
    print(f"phase13-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
