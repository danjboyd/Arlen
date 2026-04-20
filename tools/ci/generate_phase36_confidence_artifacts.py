#!/usr/bin/env python3
"""Generate Phase 36 confidence artifacts from deploy UX smoke outputs."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase36-confidence-v1"


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"expected object JSON at {path}")
    return payload


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def release_ids(payload: Dict[str, Any]) -> set[str]:
    releases = payload.get("releases")
    if not isinstance(releases, list):
        return set()
    ids: set[str] = set()
    for entry in releases:
        if isinstance(entry, dict) and isinstance(entry.get("id"), str):
            ids.add(entry["id"])
    return ids


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 36 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase36")
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    list_no_config = load_json(output_dir / "list_no_config.json")
    target_sample_write = load_json(output_dir / "target_sample_write.json")
    list_sample_config = load_json(output_dir / "list_sample_config.json")
    list_two_targets = load_json(output_dir / "list_two_targets.json")
    dryrun_alpha = load_json(output_dir / "dryrun_alpha.json")
    plan_alias_alpha = load_json(output_dir / "plan_alias_alpha.json")
    push_a = load_json(output_dir / "push_phase36_a.json")
    push_b = load_json(output_dir / "push_phase36_b.json")
    releases_after_pushes = load_json(output_dir / "releases_after_pushes.json")
    uninitialized_push = load_json(output_dir / "uninitialized_push.json")

    completion_bash = read_text(output_dir / "completion.bash")
    completion_powershell = read_text(output_dir / "completion.ps1")
    candidates_top_level = read_text(output_dir / "candidates_top_level.txt")
    candidates_deploy_subcommands = read_text(output_dir / "candidates_deploy_subcommands.txt")
    candidates_deploy_target_subcommands = read_text(output_dir / "candidates_deploy_target_subcommands.txt")
    candidates_deploy_options = read_text(output_dir / "candidates_deploy_options.txt")
    candidates_deploy_targets = read_text(output_dir / "candidates_deploy_targets.txt")
    candidates_malformed_targets = read_text(output_dir / "candidates_malformed_targets.txt")
    completion_release_ids_remote = read_text(output_dir / "completion_release_ids_remote_target.txt")
    mock_ssh_log = read_text(output_dir / "mock_ssh.log")
    integration_sample_completion = read_text(output_dir / "integration_sample_completion.log")
    integration_remote_reuse = read_text(output_dir / "integration_remote_reuse.log")
    uninitialized_exit = read_text(output_dir / "uninitialized_push.exit").strip()

    two_target_names = [
        entry.get("name")
        for entry in list_two_targets.get("targets", [])
        if isinstance(entry, dict)
    ]
    sample_targets = list_sample_config.get("targets") if isinstance(list_sample_config.get("targets"), list) else []
    sample_target = sample_targets[0] if sample_targets and isinstance(sample_targets[0], dict) else {}
    available_releases = release_ids(releases_after_pushes)

    checks = {
        "deploy_list_no_config": list_no_config.get("workflow") == "deploy.list"
        and list_no_config.get("target_count") == 0
        and list_no_config.get("status") == "ok",
        "deploy_list_two_targets": list_two_targets.get("workflow") == "deploy.list"
        and list_two_targets.get("target_count") == 2
        and two_target_names == ["alpha", "beta"],
        "dryrun_and_plan_alias": dryrun_alpha.get("workflow") == "deploy.dryrun"
        and dryrun_alpha.get("status") == "planned"
        and plan_alias_alpha.get("workflow") == "deploy.dryrun"
        and plan_alias_alpha.get("status") == "planned"
        and plan_alias_alpha.get("deprecated_alias") == "plan",
        "sample_config_parses": target_sample_write.get("workflow") == "deploy.target.sample"
        and target_sample_write.get("written") is True
        and sample_target.get("name") == "production"
        and sample_target.get("ssh_host") == "deploy@prod.example.test",
        "uninitialized_target_guard": uninitialized_exit == "1"
        and uninitialized_push.get("status") == "error"
        and uninitialized_push.get("error", {}).get("code") == "deploy_target_not_initialized",
        "local_releases_after_pushes": push_a.get("status") == "ok"
        and push_b.get("status") == "ok"
        and releases_after_pushes.get("workflow") == "deploy.releases"
        and {"phase36-a", "phase36-b"}.issubset(available_releases),
        "completion_generation": "complete -F _arlen_complete arlen" in completion_bash
        and "arlen completion candidates deploy-target-subcommands" in completion_bash
        and "Register-ArgumentCompleter" in completion_powershell,
        "completion_candidates": "deploy" in candidates_top_level.splitlines()
        and "dryrun" in candidates_deploy_subcommands.splitlines()
        and "target" in candidates_deploy_subcommands.splitlines()
        and "sample" in candidates_deploy_target_subcommands.splitlines()
        and "--write" in candidates_deploy_options.splitlines()
        and "production" in candidates_deploy_targets.splitlines(),
        "completion_safety": candidates_malformed_targets.strip() == ""
        and completion_release_ids_remote.strip() == ""
        and mock_ssh_log.strip() == "",
        "focused_integration_tests": "1 tests PASSED" in integration_sample_completion
        and "1 tests PASSED" in integration_remote_reuse,
    }
    overall_status = "pass" if all(checks.values()) else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    artifact_names = [
        "arlen-build.log",
        "list_no_config.json",
        "target_sample_write.json",
        "list_sample_config.json",
        "list_two_targets.json",
        "dryrun_alpha.json",
        "plan_alias_alpha.json",
        "push_phase36_a.json",
        "push_phase36_b.json",
        "releases_after_pushes.json",
        "uninitialized_push.json",
        "uninitialized_push.exit",
        "completion.bash",
        "completion.ps1",
        "candidates_top_level.txt",
        "candidates_deploy_subcommands.txt",
        "candidates_deploy_target_subcommands.txt",
        "candidates_deploy_options.txt",
        "candidates_deploy_targets.txt",
        "candidates_malformed_targets.txt",
        "completion_release_ids_remote_target.txt",
        "mock_ssh.log",
        "integration_sample_completion.log",
        "integration_remote_reuse.log",
    ]

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "checks": checks,
        "artifacts": artifact_names,
    }
    write_json(output_dir / "phase36_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 36 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Deploy UX checks:",
            f"- no-config `deploy list`: `{checks['deploy_list_no_config']}`",
            f"- two-target `deploy list`: `{checks['deploy_list_two_targets']}`",
            f"- `dryrun` plus `plan` alias: `{checks['dryrun_and_plan_alias']}`",
            f"- sample config writes and parses: `{checks['sample_config_parses']}`",
            f"- uninitialized remote mutation guard: `{checks['uninitialized_target_guard']}`",
            f"- releases list after multiple pushes: `{checks['local_releases_after_pushes']}`",
            "",
            "Completion checks:",
            f"- bash and PowerShell generation: `{checks['completion_generation']}`",
            f"- static and dynamic candidates: `{checks['completion_candidates']}`",
            f"- malformed config and remote target candidates are side-effect free: `{checks['completion_safety']}`",
            "",
            "Focused integration tests:",
            f"- sample/completion and remote reuse tests: `{checks['focused_integration_tests']}`",
            "",
            "Focused entrypoint:",
            "",
            "- `make phase36-confidence`",
            "",
        ]
    )
    (output_dir / "phase36_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": ["phase36_confidence_eval.json", "phase36_confidence.md", *artifact_names],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase36-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
