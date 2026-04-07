#!/usr/bin/env python3
"""Generate Phase 29 confidence artifacts from deploy CLI and reserved-endpoint smoke outputs."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase29-confidence-v1"


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


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 29 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase29")
    parser.add_argument("--deploy-push-a", required=True)
    parser.add_argument("--deploy-push-b", required=True)
    parser.add_argument("--deploy-release", required=True)
    parser.add_argument("--deploy-status", required=True)
    parser.add_argument("--deploy-doctor", required=True)
    parser.add_argument("--deploy-rollback", required=True)
    parser.add_argument("--deploy-logs", required=True)
    parser.add_argument("--reserved-prepare-log", required=True)
    parser.add_argument("--reserved-health", required=True)
    parser.add_argument("--reserved-ready", required=True)
    parser.add_argument("--reserved-metrics", required=True)
    parser.add_argument("--reserved-shadow", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    push_a = load_json(Path(args.deploy_push_a).resolve())
    push_b = load_json(Path(args.deploy_push_b).resolve())
    release = load_json(Path(args.deploy_release).resolve())
    status = load_json(Path(args.deploy_status).resolve())
    doctor = load_json(Path(args.deploy_doctor).resolve())
    rollback = load_json(Path(args.deploy_rollback).resolve())
    logs = load_json(Path(args.deploy_logs).resolve())
    reserved_prepare_log = text(Path(args.reserved_prepare_log).resolve())
    reserved_health = text(Path(args.reserved_health).resolve())
    reserved_ready = text(Path(args.reserved_ready).resolve())
    reserved_metrics = text(Path(args.reserved_metrics).resolve())
    reserved_shadow = text(Path(args.reserved_shadow).resolve())

    checks = {
        "deploy_push_a": push_a.get("status") == "ok",
        "deploy_push_b": push_b.get("status") == "ok",
        "deploy_release": release.get("status") == "ok",
        "deploy_status": status.get("status") == "ok" and status.get("active_release_id") == "rel-b" and status.get("previous_release_id") == "rel-a",
        "deploy_doctor": doctor.get("status") in {"ok", "warn"},
        "deploy_rollback": rollback.get("status") == "ok" and rollback.get("active_release_id") == "rel-a",
        "deploy_logs": logs.get("status") == "ok" and logs.get("log_source") == "file" and "line-b" in str(logs.get("captured_output", "")),
        "reserved_prepare": "prepare-only mode" in reserved_prepare_log,
        "reserved_health": reserved_health == "ok\n",
        "reserved_ready": reserved_ready == "ready\n",
        "reserved_metrics": "aln_http_requests_total" in reserved_metrics,
        "reserved_shadow": reserved_shadow == "token:shadowed\n",
    }
    overall_status = "pass" if all(checks.values()) else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "checks": checks,
        "artifacts": [
            Path(args.deploy_push_a).name,
            Path(args.deploy_push_b).name,
            Path(args.deploy_release).name,
            Path(args.deploy_status).name,
            Path(args.deploy_doctor).name,
            Path(args.deploy_rollback).name,
            Path(args.deploy_logs).name,
            Path(args.reserved_prepare_log).name,
            Path(args.reserved_health).name,
            Path(args.reserved_ready).name,
            Path(args.reserved_metrics).name,
            Path(args.reserved_shadow).name,
        ],
    }
    write_json(output_dir / "phase29_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 29 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Deploy CLI checks:",
            f"- `deploy push` (rel-a): `{checks['deploy_push_a']}`",
            f"- `deploy push` (rel-b): `{checks['deploy_push_b']}`",
            f"- `deploy release`: `{checks['deploy_release']}`",
            f"- `deploy status`: `{checks['deploy_status']}`",
            f"- `deploy doctor`: `{checks['deploy_doctor']}`",
            f"- `deploy rollback`: `{checks['deploy_rollback']}`",
            f"- `deploy logs`: `{checks['deploy_logs']}`",
            "",
            "Reserved operability endpoint checks:",
            f"- prepare-only smoke: `{checks['reserved_prepare']}`",
            f"- `/healthz`: `{checks['reserved_health']}`",
            f"- `/readyz`: `{checks['reserved_ready']}`",
            f"- `/metrics`: `{checks['reserved_metrics']}`",
            f"- catch-all route still works on non-reserved paths: `{checks['reserved_shadow']}`",
            "",
            "Focused entrypoint:",
            "",
            "- `make phase29-confidence`",
            "",
        ]
    )
    (output_dir / "phase29_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase29_confidence_eval.json",
            "phase29_confidence.md",
            Path(args.deploy_push_a).name,
            Path(args.deploy_push_b).name,
            Path(args.deploy_release).name,
            Path(args.deploy_status).name,
            Path(args.deploy_doctor).name,
            Path(args.deploy_rollback).name,
            Path(args.deploy_logs).name,
            Path(args.reserved_prepare_log).name,
            Path(args.reserved_health).name,
            Path(args.reserved_ready).name,
            Path(args.reserved_metrics).name,
            Path(args.reserved_shadow).name,
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase29-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
