#!/usr/bin/env python3
"""Generate Phase 19 confidence artifacts from timing logs and scope probes."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase19-confidence-v1"
COMMAND_DEFINITIONS = {
    "build_tests_cold": {
        "label": "make build-tests (cold)",
        "required_markers": [],
    },
    "build_tests_warm": {
        "label": "make build-tests (warm)",
        "required_markers": ["Nothing to be done for 'build-tests'."],
    },
    "test_unit": {
        "label": "make test-unit",
        "required_markers": ["PASSED"],
    },
    "boomhauer_prepare_cold": {
        "label": "boomhauer --prepare-only (cold app cache)",
        "required_markers": [
            "boomhauer: prepare-only mode; building app artifacts without starting the server",
            "boomhauer: [1/4]",
            "boomhauer: [2/4] transpiling templates",
            "boomhauer: [3/4]",
            "boomhauer: [4/4]",
        ],
    },
    "boomhauer_prepare_warm": {
        "label": "boomhauer --prepare-only (warm app cache)",
        "required_markers": [
            "boomhauer: prepare-only mode; building app artifacts without starting the server",
            "boomhauer: [3/4] reusing current app objects",
            "boomhauer: [4/4] reusing current app binary",
        ],
    },
    "boomhauer_print_routes": {
        "label": "boomhauer --print-routes",
        "required_markers": [
            "boomhauer: route inspection mode; ensuring artifacts are current before printing routes",
            "GET / ->",
        ],
    },
}
SCOPE_EXPECTATIONS = {
    "framework": {
        "framework_compile": "yes",
        "framework_archive": "yes",
        "root_transpile": "no",
        "template_index_compile": "no",
        "template_layout_compile": "no",
        "unit_test_compile": "no",
        "unit_bundle_link": "yes",
        "integration_bundle_link": "yes",
        "boomhauer_link": "yes",
    },
    "template": {
        "framework_compile": "no",
        "framework_archive": "no",
        "root_transpile": "yes",
        "template_index_compile": "yes",
        "template_layout_compile": "no",
        "unit_test_compile": "no",
        "unit_bundle_link": "yes",
        "integration_bundle_link": "yes",
        "boomhauer_link": "yes",
    },
    "unittest": {
        "framework_compile": "no",
        "framework_archive": "no",
        "root_transpile": "no",
        "template_index_compile": "no",
        "template_layout_compile": "no",
        "unit_test_compile": "yes",
        "unit_bundle_link": "yes",
        "integration_bundle_link": "no",
        "boomhauer_link": "no",
    },
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


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def parse_command(output_dir: Path, name: str) -> Dict[str, Any]:
    definition = COMMAND_DEFINITIONS[name]
    log_path = output_dir / f"{name}.log"
    time_path = output_dir / f"{name}.time"
    exit_path = output_dir / f"{name}.exitcode"
    command_path = output_dir / f"{name}.command"
    log_text = read_text(log_path)
    command_text = read_text(command_path).strip()
    try:
        exit_code = int(read_text(exit_path).strip() or "1")
    except ValueError:
        exit_code = 1
    duration_seconds = 0.0
    for line in reversed(read_text(time_path).splitlines()):
        try:
            duration_seconds = float(line.strip())
            break
        except ValueError:
            continue

    missing_markers = [marker for marker in definition["required_markers"] if marker not in log_text]
    summary = ""
    for line in reversed(log_text.splitlines()):
        stripped = line.strip()
        if stripped:
            summary = stripped
            break

    status = "passed" if exit_code == 0 and not missing_markers else "failed"
    return {
        "label": definition["label"],
        "status": status,
        "exit_code": exit_code,
        "duration_seconds": duration_seconds,
        "command": command_text,
        "log": log_path.name,
        "summary": summary,
        "required_markers": definition["required_markers"],
        "missing_markers": missing_markers,
    }


def parse_scope(output_dir: Path, name: str) -> Dict[str, Any]:
    path = output_dir / f"{name}.scope"
    values: Dict[str, str] = {}
    for line in read_text(path).splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()

    exit_code = values.get("exit_code", "missing")
    expected = SCOPE_EXPECTATIONS[name]
    mismatches = []
    for key, expected_value in expected.items():
        actual = values.get(key, "missing")
        if actual != expected_value:
            mismatches.append({"key": key, "expected": expected_value, "actual": actual})

    skipped = exit_code == "skipped"
    status = "skipped" if skipped else "passed"
    if skipped:
        mismatches = []
    if not skipped and (exit_code != "0" or mismatches):
        status = "failed"

    return {
        "status": status,
        "probe": path.name,
        "exit_code": exit_code,
        "reason": values.get("reason", ""),
        "expected": expected,
        "actual": {key: values.get(key, "missing") for key in expected},
        "mismatches": mismatches,
    }


def render_markdown(
    app_root: Path,
    commands: Dict[str, Dict[str, Any]],
    scopes: Dict[str, Dict[str, Any]],
    overall_status: str,
) -> str:
    lines = [
        "# Phase 19 Confidence",
        "",
        f"- status: `{overall_status}`",
        f"- app root: `{app_root}`",
        "",
        "## Command Timings",
        "",
    ]
    for name in COMMAND_DEFINITIONS:
        command = commands[name]
        lines.append(
            f"- {command['label']}: `{command['status']}` in `{command['duration_seconds']:.3f}s`"
        )
        if command["missing_markers"]:
            for marker in command["missing_markers"]:
                lines.append(f"  - missing marker: `{marker}`")
    lines.extend(["", "## Incremental Scope", ""])
    for name in ("framework", "template", "unittest"):
        scope = scopes[name]
        lines.append(f"- {name}: `{scope['status']}`")
        if scope["reason"]:
            lines.append(f"  - reason: `{scope['reason']}`")
        for mismatch in scope["mismatches"]:
            lines.append(
                "  - mismatch: "
                f"`{mismatch['key']}` expected `{mismatch['expected']}` got `{mismatch['actual']}`"
            )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 19 confidence artifacts")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase19")
    parser.add_argument("--app-root", required=True)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    app_root = Path(args.app_root).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    commands = {name: parse_command(output_dir, name) for name in COMMAND_DEFINITIONS}
    scopes = {name: parse_scope(output_dir, name) for name in SCOPE_EXPECTATIONS}

    overall_status = "passed"
    if any(command["status"] != "passed" for command in commands.values()):
        overall_status = "failed"
    if any(scope["status"] != "passed" for scope in scopes.values()):
        overall_status = "failed"

    generated_at = datetime.now(timezone.utc).isoformat()
    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "git_commit": git_commit(repo_root),
        "status": overall_status,
        "app_root": str(app_root),
        "commands": commands,
        "incremental_scope": scopes,
    }
    write_json(output_dir / "phase19_confidence_eval.json", eval_payload)
    (output_dir / "phase19_confidence.md").write_text(
        render_markdown(app_root, commands, scopes, overall_status),
        encoding="utf-8",
    )
    write_json(
        output_dir / "manifest.json",
        {
            "version": VERSION,
            "generated_at": generated_at,
            "git_commit": eval_payload["git_commit"],
            "status": overall_status,
            "artifacts": [
                "phase19_confidence_eval.json",
                "phase19_confidence.md",
                "build_tests_cold.log",
                "build_tests_warm.log",
                "test_unit.log",
                "boomhauer_prepare_cold.log",
                "boomhauer_prepare_warm.log",
                "boomhauer_print_routes.log",
                "framework.scope",
                "template.scope",
                "unittest.scope",
            ],
        },
    )
    print(f"phase19-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
