#!/usr/bin/env python3
import json
import os
import sys
from datetime import datetime, timezone


def is_absolute(path: str) -> bool:
    return os.path.isabs(path) or path.startswith("\\\\")


def resolve_release_path(release_dir: str, value: str, default_relative: str) -> str:
    candidate = (value or "").strip() or default_relative
    if is_absolute(candidate):
        return os.path.normpath(candidate)
    return os.path.normpath(os.path.join(release_dir, candidate))


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: write_release_env.py <release-dir>", file=sys.stderr)
        return 2

    release_dir = os.path.abspath(sys.argv[1])
    manifest_path = os.path.join(release_dir, "metadata", "manifest.json")
    output_path = os.path.join(release_dir, "metadata", "release.env")

    if not os.path.isdir(release_dir):
        print(f"write_release_env.py: release not found: {release_dir}", file=sys.stderr)
        return 1

    manifest = {}
    if os.path.isfile(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as handle:
            manifest = json.load(handle) or {}

    paths = manifest.get("paths") or {}
    deployment = manifest.get("deployment") or {}
    handoff = manifest.get("propane_handoff") or {}
    certification = manifest.get("certification") or {}
    json_performance = manifest.get("json_performance") or {}

    values = {
        "RELEASE_ID": manifest.get("release_id") or os.path.basename(release_dir),
        "RELEASE_CREATED_UTC": manifest.get("created_utc") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "ARLEN_RELEASE_ENV_LAYOUT": "target-absolute",
        "ARLEN_RELEASE_ROOT": release_dir,
        "ARLEN_APP_ROOT": resolve_release_path(release_dir, paths.get("app_root"), "app"),
        "ARLEN_FRAMEWORK_ROOT": resolve_release_path(release_dir, paths.get("framework_root"), "framework"),
        "ARLEN_RELEASE_MANIFEST": manifest_path,
        "ARLEN_RELEASE_RUNTIME_BINARY": resolve_release_path(release_dir, paths.get("runtime_binary"), "app/.boomhauer/build/boomhauer-app"),
        "ARLEN_RELEASE_FRAMEWORK_BOOMHAUER": resolve_release_path(release_dir, paths.get("boomhauer"), "framework/build/boomhauer"),
        "ARLEN_RELEASE_ARLEN_BINARY": resolve_release_path(release_dir, paths.get("arlen"), "framework/build/arlen"),
        "ARLEN_RELEASE_PROPANE": resolve_release_path(
            release_dir, handoff.get("manager_binary") or paths.get("propane"), "framework/bin/propane"
        ),
        "ARLEN_RELEASE_JOBS_WORKER": resolve_release_path(
            release_dir, handoff.get("jobs_worker_binary") or paths.get("jobs_worker"), "framework/bin/jobs-worker"
        ),
        "ARLEN_RELEASE_OPERABILITY_PROBE_HELPER": resolve_release_path(
            release_dir, paths.get("operability_probe_helper"), "framework/tools/deploy/validate_operability.sh"
        ),
        "ARLEN_RELEASE_CERTIFICATION_STATUS": certification.get("status") or "unknown",
        "ARLEN_RELEASE_CERTIFICATION_MANIFEST": resolve_release_path(
            release_dir, certification.get("manifest_path"), "metadata/certification/manifest.json"
        ),
        "ARLEN_JSON_PERFORMANCE_STATUS": json_performance.get("status") or "unknown",
        "ARLEN_JSON_PERFORMANCE_MANIFEST": resolve_release_path(
            release_dir, json_performance.get("manifest_path"), "metadata/json_performance/manifest.json"
        ),
        "ARLEN_DEPLOY_LOCAL_PROFILE": deployment.get("local_profile") or "",
        "ARLEN_DEPLOY_TARGET_PROFILE": deployment.get("target_profile") or "",
        "ARLEN_DEPLOY_RUNTIME_STRATEGY": deployment.get("runtime_strategy") or "system",
        "ARLEN_DEPLOY_SUPPORT_LEVEL": deployment.get("support_level") or "supported",
        "ARLEN_DEPLOY_COMPATIBILITY_REASON": deployment.get("compatibility_reason") or "same_profile",
        "ARLEN_DEPLOY_ALLOW_REMOTE_REBUILD": "1" if deployment.get("allow_remote_rebuild") else "0",
        "ARLEN_DEPLOY_REMOTE_REBUILD_REQUIRED": "1" if deployment.get("remote_rebuild_required") else "0",
        "ARLEN_DEPLOY_PROPANE_MANAGER_BINARY": resolve_release_path(
            release_dir, handoff.get("manager_binary") or paths.get("propane"), "framework/bin/propane"
        ),
        "ARLEN_DEPLOY_PROPANE_ACCESSORIES_CONFIG_KEY": handoff.get("accessories_config_key") or "propaneAccessories",
        "ARLEN_DEPLOY_PROPANE_RUNTIME_ACTION_DEFAULT": handoff.get("runtime_action_default") or "reload",
        "ARLEN_DEPLOY_PROPANE_JOB_WORKER_BINARY": resolve_release_path(
            release_dir, handoff.get("jobs_worker_binary") or paths.get("jobs_worker"), "framework/bin/jobs-worker"
        ),
    }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
