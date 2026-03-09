#!/usr/bin/env python3
"""Generate Phase 12 confidence artifacts from unit logs and sample app flows."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List


VERSION = "phase12-confidence-v1"


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
        "oidc_client_suite": "XCTest:   Running OIDCClientTests",
        "provider_preset_merge_test": "testProviderPresetConfigMergesDeterministicallyWithExplicitOverrides",
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


def evaluate_login_flow(payload: Dict[str, Any]) -> Dict[str, Any]:
    session = payload.get("session")
    if not isinstance(session, dict):
        session = {}
    methods = session.get("methods")
    if not isinstance(methods, list):
        methods = []

    checks = {
        "subject": session.get("subject") == "user:oidc-user@example.com",
        "provider": session.get("provider") == "stub_oidc",
        "aal": session.get("aal") == 1,
        "federated_method": "federated" in methods,
    }
    return {
        "status": "passed" if all(checks.values()) else "failed",
        "checks": checks,
        "session": session,
    }


def evaluate_step_up_flow(payload: Dict[str, Any]) -> Dict[str, Any]:
    secure_before = payload.get("secure_before")
    step_up = payload.get("step_up")
    secure_after = payload.get("secure_after")
    if not isinstance(secure_before, dict):
        secure_before = {}
    if not isinstance(step_up, dict):
        step_up = {}
    if not isinstance(secure_after, dict):
        secure_after = {}

    secure_before_body = secure_before.get("body")
    step_up_body = step_up.get("body")
    secure_after_body = secure_after.get("body")
    if not isinstance(secure_before_body, dict):
        secure_before_body = {}
    if not isinstance(step_up_body, dict):
        step_up_body = {}
    if not isinstance(secure_after_body, dict):
        secure_after_body = {}

    secure_before_error = secure_before_body.get("error")
    step_up_session = step_up_body.get("session")
    secure_after_session = secure_after_body.get("session")
    if not isinstance(secure_before_error, dict):
        secure_before_error = {}
    if not isinstance(step_up_session, dict):
        step_up_session = {}
    if not isinstance(secure_after_session, dict):
        secure_after_session = {}

    checks = {
        "pre_step_up_denied": secure_before.get("status") == 403
        and secure_before_error.get("code") == "step_up_required",
        "step_up_aal2": step_up.get("status") == 200 and step_up_session.get("aal") == 2,
        "post_step_up_allowed": secure_after.get("status") == 200 and secure_after_session.get("aal") == 2,
    }
    return {
        "status": "passed" if all(checks.values()) else "failed",
        "checks": checks,
        "secure_before": secure_before,
        "step_up": step_up,
        "secure_after": secure_after,
    }


def render_markdown(
    unit_summary: Dict[str, Any],
    fixture: Dict[str, Any],
    login_summary: Dict[str, Any],
    step_up_summary: Dict[str, Any],
    overall_status: str,
) -> str:
    scenario_ids: List[str] = []
    scenarios = fixture.get("scenarios")
    if isinstance(scenarios, list):
        for entry in scenarios:
            if isinstance(entry, dict) and isinstance(entry.get("id"), str):
                scenario_ids.append(entry["id"])

    lines = [
        "# Phase 12 Confidence",
        "",
        f"- status: `{overall_status}`",
        f"- unit suite: `{unit_summary['status']}`",
        f"- OIDC fixture scenarios: `{len(scenario_ids)}`",
        f"- auth-primitives login flow: `{login_summary['status']}`",
        f"- auth-primitives step-up flow: `{step_up_summary['status']}`",
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
            "## OIDC Fixture",
            "",
            f"- version: `{fixture.get('version', 'unknown')}`",
        ]
    )
    for scenario_id in scenario_ids:
        lines.append(f"- scenario: `{scenario_id}`")
    lines.extend(
        [
            "",
            "## Sample App Flows",
            "",
            f"- provider login session subject: `{login_summary['session'].get('subject', '')}`",
            f"- provider login session provider: `{login_summary['session'].get('provider', '')}`",
            f"- provider login session aal: `{login_summary['session'].get('aal', '')}`",
            f"- pre-step-up status: `{step_up_summary['secure_before'].get('status', '')}`",
            f"- post-step-up status: `{step_up_summary['secure_after'].get('status', '')}`",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 12 confidence artifacts")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase12")
    parser.add_argument("--unit-log", required=True)
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--login-flow", required=True)
    parser.add_argument("--step-up-flow", required=True)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    unit_summary = parse_unit_log(Path(args.unit_log))
    fixture = load_json(Path(args.fixture))
    login_summary = evaluate_login_flow(load_json(Path(args.login_flow)))
    step_up_summary = evaluate_step_up_flow(load_json(Path(args.step_up_flow)))

    overall_status = (
        "passed"
        if unit_summary["status"] == "passed"
        and login_summary["status"] == "passed"
        and step_up_summary["status"] == "passed"
        else "failed"
    )

    eval_payload = {
        "version": VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "git_commit": git_commit(repo_root),
        "status": overall_status,
        "unit_suite": unit_summary,
        "fixture": {
            "version": fixture.get("version", "unknown"),
            "scenario_count": len(fixture.get("scenarios", [])) if isinstance(fixture.get("scenarios"), list) else 0,
            "path": Path(args.fixture).name,
        },
        "sample_app_flows": {
            "provider_login": login_summary,
            "local_step_up_after_provider_login": step_up_summary,
        },
    }
    write_json(output_dir / "phase12_confidence_eval.json", eval_payload)

    markdown = render_markdown(unit_summary, fixture, login_summary, step_up_summary, overall_status)
    (output_dir / "phase12_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": eval_payload["generated_at"],
        "git_commit": eval_payload["git_commit"],
        "status": overall_status,
        "artifacts": [
            "phase12_confidence_eval.json",
            "phase12_confidence.md",
            Path(args.unit_log).name,
            Path(args.fixture).name,
            Path(args.login_flow).name,
            Path(args.step_up_flow).name,
            "auth_primitives_server.log",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase12-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
