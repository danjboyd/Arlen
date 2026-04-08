#!/usr/bin/env python3
"""Generate Phase 31 confidence artifacts from packaged release smoke and `.exe` fallback checks."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase31-confidence-v1"


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
    parser = argparse.ArgumentParser(description="Generate Phase 31 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase31")
    parser.add_argument("--release-smoke", required=True)
    parser.add_argument("--packaged-manifest", required=True)
    parser.add_argument("--packaged-release-env", required=True)
    parser.add_argument("--deploy-doctor", required=True)
    parser.add_argument("--packaged-server-log", required=True)
    parser.add_argument("--jobs-worker-log", required=True)
    parser.add_argument("--jobs-worker-exit", required=True)
    parser.add_argument("--exe-manifest-doctor", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    release_smoke = load_json(Path(args.release_smoke).resolve())
    packaged_manifest = load_json(Path(args.packaged_manifest).resolve())
    deploy_doctor = load_json(Path(args.deploy_doctor).resolve())
    exe_manifest_doctor = load_json(Path(args.exe_manifest_doctor).resolve())
    packaged_release_env = text(Path(args.packaged_release_env).resolve())
    packaged_server_log = text(Path(args.packaged_server_log).resolve())
    jobs_worker_log = text(Path(args.jobs_worker_log).resolve())
    jobs_worker_exit = text(Path(args.jobs_worker_exit).resolve()).strip()

    manifest_paths = packaged_manifest.get("paths") if isinstance(packaged_manifest.get("paths"), dict) else {}
    doctor_checks = deploy_doctor.get("checks") if isinstance(deploy_doctor.get("checks"), list) else []
    exe_checks = exe_manifest_doctor.get("checks") if isinstance(exe_manifest_doctor.get("checks"), list) else []
    doctor_index = {entry.get("id"): entry.get("status") for entry in doctor_checks if isinstance(entry, dict)}
    exe_index = {entry.get("id"): entry.get("status") for entry in exe_checks if isinstance(entry, dict)}

    checks = {
        "release_smoke": release_smoke.get("status") == "ok",
        "packaged_manifest_paths": all(
            isinstance(manifest_paths.get(key), str) and len(manifest_paths[key]) > 0
            for key in ("runtime_binary", "boomhauer", "propane", "jobs_worker", "arlen", "operability_probe_helper")
        ),
        "packaged_release_env": "ARLEN_RELEASE_MANIFEST=" in packaged_release_env
        and "ARLEN_RELEASE_PROPANE=" in packaged_release_env
        and "ARLEN_RELEASE_JOBS_WORKER=" in packaged_release_env,
        "packaged_deploy_doctor": deploy_doctor.get("status") in {"ok", "warn"} and doctor_index.get("operability") == "pass",
        "packaged_server_log": "Traceback" not in packaged_server_log and "Assertion FAILED" not in packaged_server_log,
        "packaged_jobs_worker": jobs_worker_exit == "0"
        or "ALNJobsModuleRuntime is unavailable in this app binary" in jobs_worker_log,
        "exe_manifest_doctor": exe_manifest_doctor.get("status") in {"ok", "warn"}
        and exe_index.get("runtime_binary") == "pass"
        and exe_index.get("boomhauer") == "pass"
        and exe_index.get("arlen") == "pass"
        and exe_index.get("jobs_worker") == "pass",
    }
    overall_status = "pass" if all(checks.values()) else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "checks": checks,
        "artifacts": [
            Path(args.release_smoke).name,
            Path(args.packaged_manifest).name,
            Path(args.packaged_release_env).name,
            Path(args.deploy_doctor).name,
            Path(args.packaged_server_log).name,
            Path(args.jobs_worker_log).name,
            Path(args.jobs_worker_exit).name,
            Path(args.exe_manifest_doctor).name,
        ],
    }
    write_json(output_dir / "phase31_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 31 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Packaged release checks:",
            f"- release smoke workflow: `{checks['release_smoke']}`",
            f"- packaged manifest runtime/helper paths: `{checks['packaged_manifest_paths']}`",
            f"- packaged release env metadata: `{checks['packaged_release_env']}`",
            f"- packaged `deploy doctor --base-url`: `{checks['packaged_deploy_doctor']}`",
            f"- packaged runtime server log stayed clean: `{checks['packaged_server_log']}`",
            f"- packaged `jobs-worker --once`: `{checks['packaged_jobs_worker']}`",
            "",
            "Windows `.exe` fallback check:",
            f"- manifest base names resolve `.exe` siblings in `deploy doctor`: `{checks['exe_manifest_doctor']}`",
            "",
            "Focused entrypoint:",
            "",
            "- `make phase31-confidence`",
            "",
        ]
    )
    (output_dir / "phase31_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase31_confidence_eval.json",
            "phase31_confidence.md",
            Path(args.release_smoke).name,
            Path(args.packaged_manifest).name,
            Path(args.packaged_release_env).name,
            Path(args.deploy_doctor).name,
            Path(args.packaged_server_log).name,
            Path(args.jobs_worker_log).name,
            Path(args.jobs_worker_exit).name,
            Path(args.exe_manifest_doctor).name,
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase31-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
