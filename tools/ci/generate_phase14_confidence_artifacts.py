#!/usr/bin/env python3
"""Generate Phase 14 confidence artifacts from unit logs and sample app flows."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable


VERSION = "phase14-confidence-v1"
EXPECTED_MODULES = {"auth", "admin-ui", "jobs", "notifications", "storage", "ops", "search"}
EXPECTED_OPENAPI_PATHS = {
    "/jobs/api/enqueue",
    "/notifications/api/preview",
    "/storage/api/upload-sessions",
    "/ops/api/summary",
    "/search/api/resources/{resource}/query",
}


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
        "phase14a_suite": "XCTest:   Running Phase14ATests",
        "phase14b_suite": "XCTest:   Running Phase14BTests",
        "phase14c_suite": "XCTest:   Running Phase14CTests",
        "phase14d_suite": "XCTest:   Running Phase14DTests",
        "phase14e_suite": "XCTest:   Running Phase14ETests",
        "phase14f_suite": "XCTest:   Running Phase14FTests",
        "phase14g_suite": "XCTest:   Running Phase14GTests",
        "phase14h_suite": "XCTest:   Running Phase14HTests",
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


def _dict(payload: Dict[str, Any], key: str) -> Dict[str, Any]:
    value = payload.get(key)
    return value if isinstance(value, dict) else {}


def _list(payload: Dict[str, Any], key: str) -> list[Any]:
    value = payload.get(key)
    return value if isinstance(value, list) else []


def _set_from_path_strings(values: Iterable[Any]) -> set[str]:
    output: set[str] = set()
    for value in values:
        if isinstance(value, str) and value:
            output.add(value)
    return output


def evaluate_runtime(
    module_list: Dict[str, Any],
    doctor: Dict[str, Any],
    migrate: Dict[str, Any],
    assets: Dict[str, Any],
    flow: Dict[str, Any],
) -> Dict[str, Any]:
    installed_modules = {entry.get("identifier", "") for entry in _list(module_list, "modules") if isinstance(entry, dict)}
    staged_files = [entry for entry in _list(assets, "staged_files") if isinstance(entry, str)]

    auth = _dict(flow, "auth")
    jobs = _dict(flow, "jobs")
    notifications = _dict(flow, "notifications")
    storage = _dict(flow, "storage")
    search = _dict(flow, "search")
    ops = _dict(flow, "ops")

    manual_execs = _list(_dict(_dict(jobs, "after_manual_executions"), "body").get("data", {}), "executions")
    scheduler_execs = _list(_dict(_dict(jobs, "after_scheduler_executions"), "body").get("data", {}), "executions")
    preview_data = _dict(_dict(_dict(notifications, "preview"), "body"), "data")
    test_send_data = _dict(_dict(_dict(notifications, "test_send"), "body"), "data")
    storage_detail = _dict(_dict(_dict(storage, "detail"), "body"), "data")
    storage_object = _dict(storage_detail, "object")
    search_query = _dict(_dict(_dict(search, "query"), "body"), "data")
    search_results = _list(search_query, "results")
    admin_indexes = _list(_dict(_dict(search, "admin_indexes"), "body"), "items")
    ops_summary = _dict(_dict(_dict(ops, "summary"), "body"), "data")
    ops_openapi = _dict(_dict(_dict(ops, "openapi"), "body"), "data").get("openapi", {})
    if not isinstance(ops_openapi, dict):
        ops_openapi = {}
    openapi_paths = _set_from_path_strings(_dict(ops_openapi, "paths").keys())

    orders_index = next(
        (
            entry
            for entry in admin_indexes
            if isinstance(entry, dict) and entry.get("identifier") == "orders"
        ),
        {},
    )

    checks = {
        "modules_installed": EXPECTED_MODULES.issubset(installed_modules),
        "doctor_ok": doctor.get("status") == "ok",
        "migrate_ok": migrate.get("status") == "ok",
        "assets_generated": bool(staged_files)
        and any(path.endswith("/modules/ops/ops.css") for path in staged_files)
        and any(path.endswith("/modules/search/search.css") for path in staged_files),
        "register_authenticated": _dict(auth, "register").get("status") == 200
        and _dict(_dict(auth, "register"), "body").get("authenticated") is True,
        "step_up_aal2": _dict(auth, "step_up").get("status") == 200
        and _dict(_dict(auth, "step_up"), "body").get("aal") == 2,
        "jobs_manual_flow": _dict(jobs, "manual_enqueue").get("status") == 200
        and _dict(jobs, "manual_worker").get("status") == 200
        and _dict(_dict(jobs, "manual_worker"), "body").get("data", {}).get("acknowledgedCount") == 1
        and "manual-job" in manual_execs,
        "jobs_scheduler_flow": _dict(jobs, "scheduler").get("status") == 200
        and _dict(_dict(jobs, "scheduler"), "body").get("data", {}).get("triggeredCount") == 1
        and _dict(jobs, "scheduler_worker").get("status") == 200
        and _dict(_dict(jobs, "scheduler_worker"), "body").get("data", {}).get("acknowledgedCount") == 1
        and "scheduled-job" in scheduler_execs,
        "notifications_preview": _dict(notifications, "preview").get("status") == 200
        and _dict(preview_data, "email").get("subject") == "Phase14 Demo Admin",
        "notifications_test_send": _dict(notifications, "test_send").get("status") == 200
        and {"email", "in_app"}.issubset(set(_list(test_send_data, "channels"))),
        "storage_flow": _dict(storage, "upload_session").get("status") == 200
        and _dict(storage, "upload").get("status") == 200
        and _dict(storage, "variant_worker").get("status") == 200
        and storage_object.get("variantState") == "ready"
        and len(_list(storage_object, "variants")) == 2
        and _dict(storage, "download").get("status") == 200
        and _dict(storage, "download").get("body") == "png!",
        "search_flow": _dict(search, "reindex").get("status") == 200
        and _dict(search, "worker").get("status") == 200
        and _dict(search, "query").get("status") == 200
        and len(search_results) == 1
        and isinstance(search_results[0], dict)
        and search_results[0].get("recordID") == "ord-101"
        and orders_index.get("documentCount") == 2,
        "ops_flow": _dict(ops, "summary").get("status") == 200
        and _dict(_dict(ops_summary, "search"), "totals").get("documents") == 2
        and _dict(ops_summary, "search").get("available") is True
        and _dict(ops, "openapi").get("status") == 200
        and EXPECTED_OPENAPI_PATHS.issubset(openapi_paths),
    }

    return {
        "status": "passed" if all(checks.values()) else "failed",
        "checks": checks,
        "installed_modules": sorted(installed_modules),
        "migrations": _list(migrate, "files"),
        "staged_files_count": len(staged_files),
        "runtime_flow": flow,
    }


def render_markdown(unit_summary: Dict[str, Any], runtime_summary: Dict[str, Any], overall_status: str) -> str:
    checks = runtime_summary.get("checks", {})
    installed = ", ".join(runtime_summary.get("installed_modules", []))
    lines = [
        "# Phase 14 Confidence",
        "",
        f"- status: `{overall_status}`",
        f"- unit suite: `{unit_summary['status']}`",
        f"- sample flow: `{runtime_summary['status']}`",
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
            f"- installed modules: `{installed}`",
            f"- migrations applied: `{len(runtime_summary.get('migrations', []))}`",
            f"- staged assets: `{runtime_summary.get('staged_files_count', 0)}`",
            f"- auth register: `{checks.get('register_authenticated')}`",
            f"- auth step-up: `{checks.get('step_up_aal2')}`",
            f"- jobs manual flow: `{checks.get('jobs_manual_flow')}`",
            f"- jobs scheduler flow: `{checks.get('jobs_scheduler_flow')}`",
            f"- notifications flow: `{checks.get('notifications_preview') and checks.get('notifications_test_send')}`",
            f"- storage flow: `{checks.get('storage_flow')}`",
            f"- search flow: `{checks.get('search_flow')}`",
            f"- ops flow: `{checks.get('ops_flow')}`",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 14 confidence artifacts")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase14")
    parser.add_argument("--unit-log", required=True)
    parser.add_argument("--module-list")
    parser.add_argument("--doctor")
    parser.add_argument("--migrate")
    parser.add_argument("--assets")
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
        write_json(output_dir / "phase14_confidence_eval.json", eval_payload)
        (output_dir / "phase14_confidence.md").write_text(
            "\n".join(
                [
                    "# Phase 14 Confidence",
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
                "artifacts": ["phase14_confidence_eval.json", "phase14_confidence.md", Path(args.unit_log).name],
            },
        )
        print(f"phase14-confidence: generated skipped artifacts in {output_dir}")
        return 0

    required_args = [args.module_list, args.doctor, args.migrate, args.assets, args.flow]
    if any(not value for value in required_args):
      raise SystemExit("--module-list, --doctor, --migrate, --assets, and --flow are required when --mode=run")

    runtime_summary = evaluate_runtime(
        load_json(Path(args.module_list)),
        load_json(Path(args.doctor)),
        load_json(Path(args.migrate)),
        load_json(Path(args.assets)),
        load_json(Path(args.flow)),
    )
    overall_status = (
        "passed" if unit_summary["status"] == "passed" and runtime_summary["status"] == "passed" else "failed"
    )
    eval_payload = {
        "version": VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "git_commit": git_commit(repo_root),
        "status": overall_status,
        "unit_suite": unit_summary,
        "sample_app_flow": runtime_summary,
    }
    write_json(output_dir / "phase14_confidence_eval.json", eval_payload)
    (output_dir / "phase14_confidence.md").write_text(
        render_markdown(unit_summary, runtime_summary, overall_status),
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
                "phase14_confidence_eval.json",
                "phase14_confidence.md",
                Path(args.unit_log).name,
                Path(args.module_list).name,
                Path(args.doctor).name,
                Path(args.migrate).name,
                Path(args.assets).name,
                Path(args.flow).name,
            ],
        },
    )
    print(f"phase14-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
