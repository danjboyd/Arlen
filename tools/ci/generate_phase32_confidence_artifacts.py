#!/usr/bin/env python3
"""Generate Phase 32 confidence artifacts from deploy compatibility and propane handoff checks."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase32-confidence-v1"


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


def check_index(payload: Dict[str, Any]) -> Dict[str, str]:
    checks = payload.get("checks") if isinstance(payload.get("checks"), list) else []
    return {
        str(entry.get("id")): str(entry.get("status"))
        for entry in checks
        if isinstance(entry, dict) and "id" in entry and "status" in entry
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 32 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase32")
    parser.add_argument("--push-supported", required=True)
    parser.add_argument("--release-supported", required=True)
    parser.add_argument("--push-experimental", required=True)
    parser.add_argument("--release-experimental", required=True)
    parser.add_argument("--doctor-experimental-fail", required=True)
    parser.add_argument("--doctor-experimental-pass", required=True)
    parser.add_argument("--status-experimental", required=True)
    parser.add_argument("--rollback", required=True)
    parser.add_argument("--unsupported-release", required=True)
    parser.add_argument("--release-env", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    push_supported = load_json(Path(args.push_supported).resolve())
    release_supported = load_json(Path(args.release_supported).resolve())
    push_experimental = load_json(Path(args.push_experimental).resolve())
    release_experimental = load_json(Path(args.release_experimental).resolve())
    doctor_experimental_fail = load_json(Path(args.doctor_experimental_fail).resolve())
    doctor_experimental_pass = load_json(Path(args.doctor_experimental_pass).resolve())
    status_experimental = load_json(Path(args.status_experimental).resolve())
    rollback = load_json(Path(args.rollback).resolve())
    unsupported_release = load_json(Path(args.unsupported_release).resolve())
    release_env = text(Path(args.release_env).resolve())

    release_experimental_steps = release_experimental.get("steps") if isinstance(release_experimental.get("steps"), list) else []
    remote_build_step_ok = any(
        isinstance(step, dict)
        and step.get("id") == "remote_build_check"
        and step.get("status") == "ok"
        for step in release_experimental_steps
    )
    doctor_fail_index = check_index(doctor_experimental_fail)
    doctor_pass_index = check_index(doctor_experimental_pass)
    status_rollback_candidate = status_experimental.get("rollback_candidate") if isinstance(status_experimental.get("rollback_candidate"), dict) else {}
    propane_handoff = status_experimental.get("propane_handoff") if isinstance(status_experimental.get("propane_handoff"), dict) else {}
    rollback_source = rollback.get("rollback_source") if isinstance(rollback.get("rollback_source"), dict) else {}

    checks = {
        "supported_release": push_supported.get("status") == "ok" and release_supported.get("status") == "ok",
        "experimental_manifest": push_experimental.get("deployment", {}).get("support_level") == "experimental"
        and push_experimental.get("deployment", {}).get("runtime_strategy") == "managed",
        "experimental_release_remote_build_check": release_experimental.get("status") == "ok" and remote_build_step_ok,
        "doctor_requires_remote_build_check": doctor_experimental_fail.get("status") == "fail"
        and doctor_fail_index.get("remote_build_check") == "fail",
        "doctor_passes_with_remote_build_check": doctor_experimental_pass.get("status") == "warn"
        and doctor_pass_index.get("remote_build_check") == "pass"
        and doctor_pass_index.get("compatibility") == "warn",
        "status_reports_rollback_candidate": status_experimental.get("status") == "ok"
        and status_rollback_candidate.get("release_id") == "phase32-a",
        "rollback_reports_source_metadata": rollback.get("status") == "ok"
        and rollback_source.get("release_id") == "phase32-b",
        "unsupported_target_rejected": unsupported_release.get("status") == "error"
        and unsupported_release.get("error", {}).get("code") == "deploy_release_unsupported_target",
        "propane_handoff_manifest": propane_handoff.get("schema") == "phase32-propane-handoff-v1"
        and propane_handoff.get("accessories_config_key") == "propaneAccessories"
        and isinstance(propane_handoff.get("manager_binary"), str)
        and len(propane_handoff.get("manager_binary", "")) > 0,
        "propane_handoff_release_env": "ARLEN_DEPLOY_PROPANE_MANAGER_BINARY=" in release_env
        and "ARLEN_DEPLOY_PROPANE_ACCESSORIES_CONFIG_KEY=propaneAccessories" in release_env
        and "ARLEN_DEPLOY_PROPANE_RUNTIME_ACTION_DEFAULT=reload" in release_env,
    }
    overall_status = "pass" if all(checks.values()) else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "checks": checks,
        "artifacts": [
          Path(args.push_supported).name,
          Path(args.release_supported).name,
          Path(args.push_experimental).name,
          Path(args.release_experimental).name,
          Path(args.doctor_experimental_fail).name,
          Path(args.doctor_experimental_pass).name,
          Path(args.status_experimental).name,
          Path(args.rollback).name,
          Path(args.unsupported_release).name,
          Path(args.release_env).name,
        ],
    }
    write_json(output_dir / "phase32_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 32 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Deploy compatibility checks:",
            f"- same-profile supported release: `{checks['supported_release']}`",
            f"- experimental manifest metadata: `{checks['experimental_manifest']}`",
            f"- experimental release requires remote build validation: `{checks['experimental_release_remote_build_check']}`",
            f"- doctor fails without remote build check: `{checks['doctor_requires_remote_build_check']}`",
            f"- doctor degrades to warn with remote build check: `{checks['doctor_passes_with_remote_build_check']}`",
            f"- status reports rollback candidate metadata: `{checks['status_reports_rollback_candidate']}`",
            f"- rollback reports source metadata: `{checks['rollback_reports_source_metadata']}`",
            f"- unsupported cross-runtime target is rejected: `{checks['unsupported_target_rejected']}`",
            "",
            "Propane handoff checks:",
            f"- manifest carries `propane` handoff contract: `{checks['propane_handoff_manifest']}`",
            f"- release env exports `propane` handoff variables: `{checks['propane_handoff_release_env']}`",
            "",
            "Focused entrypoint:",
            "",
            "- `make phase32-confidence`",
            "",
        ]
    )
    (output_dir / "phase32_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase32_confidence_eval.json",
            "phase32_confidence.md",
            Path(args.push_supported).name,
            Path(args.release_supported).name,
            Path(args.push_experimental).name,
            Path(args.release_experimental).name,
            Path(args.doctor_experimental_fail).name,
            Path(args.doctor_experimental_pass).name,
            Path(args.status_experimental).name,
            Path(args.rollback).name,
            Path(args.unsupported_release).name,
            Path(args.release_env).name,
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase32-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
