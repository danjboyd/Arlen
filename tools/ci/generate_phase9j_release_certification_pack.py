#!/usr/bin/env python3
"""Generate a Phase 9J enterprise release certification pack."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple


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


def resolve_path(repo_root: Path, raw: str) -> Path:
    candidate = Path(raw)
    if candidate.is_absolute():
        return candidate
    return (repo_root / candidate).resolve()


def safe_list_strings(value: Any) -> List[str]:
    if not isinstance(value, list):
        return []
    result: List[str] = []
    for item in value:
        if isinstance(item, str):
            result.append(item)
    return result


def parse_iso_date(raw: Any, field_name: str) -> date:
    if not isinstance(raw, str) or not raw:
        raise ValueError(f"{field_name} must be a non-empty YYYY-MM-DD string")
    try:
        return date.fromisoformat(raw)
    except Exception as exc:  # noqa: BLE001
        raise ValueError(f"{field_name} must be YYYY-MM-DD") from exc


def evaluate_phase5e(
    phase5e_dir: Path,
    manifest_required: bool,
) -> Tuple[Dict[str, Any], Dict[str, Any], List[str]]:
    manifest_path = phase5e_dir / "manifest.json"
    adapter_path = phase5e_dir / "adapter_capability_matrix_snapshot.json"
    conformance_path = phase5e_dir / "sql_builder_conformance_summary.json"

    errors: List[str] = []
    adapter_count = 0
    scenario_count = 0

    if not manifest_path.exists():
        if manifest_required:
            errors.append(f"missing required artifact: {manifest_path}")
    else:
        try:
            manifest_payload = load_json(manifest_path)
            _ = str(manifest_payload.get("version", ""))
        except Exception as exc:  # noqa: BLE001
            errors.append(f"invalid phase5e manifest: {exc}")

    if adapter_path.exists():
        try:
            adapter_payload = load_json(adapter_path)
            adapter_count = int(adapter_payload.get("adapter_count", 0))
        except Exception:
            adapter_count = 0

    if conformance_path.exists():
        try:
            conformance_payload = load_json(conformance_path)
            scenario_count = int(conformance_payload.get("scenario_count", 0))
        except Exception:
            scenario_count = 0

    status = "pass" if not errors else "fail"
    row = {
        "id": "phase5e_confidence_pack",
        "blocking": True,
        "status": status,
        "required": "phase5e manifest present and parseable",
        "observed": f"manifest_exists={manifest_path.exists()} adapter_count={adapter_count} scenario_count={scenario_count}",
        "evidence": str(manifest_path),
    }
    summary = {
        "manifest_path": str(manifest_path),
        "manifest_exists": manifest_path.exists(),
        "adapter_count": adapter_count,
        "scenario_count": scenario_count,
    }
    return row, summary, errors


def evaluate_phase9h(
    phase9h_dir: Path,
    blocking_allowed: List[str],
    tsan_allowed: List[str],
) -> Tuple[List[Dict[str, Any]], Dict[str, Any], List[str]]:
    lane_status_path = phase9h_dir / "sanitizer_lane_status.json"
    suppression_path = phase9h_dir / "sanitizer_suppression_summary.json"

    errors: List[str] = []
    lane_statuses: Dict[str, Any] = {}
    active_suppressions = 0

    if lane_status_path.exists():
        try:
            lane_payload = load_json(lane_status_path)
            lane_statuses = lane_payload.get("lane_statuses", {})
            if not isinstance(lane_statuses, dict):
                lane_statuses = {}
                errors.append("phase9h lane_statuses missing object")
        except Exception as exc:  # noqa: BLE001
            errors.append(f"invalid phase9h lane status artifact: {exc}")
    else:
        errors.append(f"missing required artifact: {lane_status_path}")

    if suppression_path.exists():
        try:
            suppression_payload = load_json(suppression_path)
            active_suppressions = int(suppression_payload.get("active_count", 0))
        except Exception:
            active_suppressions = 0

    blocking_status = str(lane_statuses.get("asan_ubsan_blocking", "missing"))
    tsan_status = str(lane_statuses.get("tsan_experimental", "missing"))

    blocking_ok = blocking_status in blocking_allowed
    tsan_ok = tsan_status in tsan_allowed

    blocking_row = {
        "id": "phase9h_blocking_sanitizers",
        "blocking": True,
        "status": "pass" if blocking_ok else "fail",
        "required": f"asan_ubsan_blocking in {blocking_allowed}",
        "observed": f"asan_ubsan_blocking={blocking_status}",
        "evidence": str(lane_status_path),
    }
    tsan_row = {
        "id": "phase9h_tsan_experimental",
        "blocking": False,
        "status": "pass" if tsan_ok else "fail",
        "required": f"tsan_experimental in {tsan_allowed}",
        "observed": f"tsan_experimental={tsan_status}",
        "evidence": str(lane_status_path),
    }

    if not blocking_ok:
        errors.append(
            f"phase9h blocking lane status {blocking_status!r} not in allowed {blocking_allowed}"
        )

    summary = {
        "lane_status_path": str(lane_status_path),
        "lane_statuses": {
            "asan_ubsan_blocking": blocking_status,
            "tsan_experimental": tsan_status,
        },
        "active_suppressions": active_suppressions,
    }
    return [blocking_row, tsan_row], summary, errors


def evaluate_phase9i(
    phase9i_dir: Path,
    max_failed_scenarios: int,
    required_seams: List[str],
) -> Tuple[Dict[str, Any], Dict[str, Any], List[str]]:
    results_path = phase9i_dir / "fault_injection_results.json"
    errors: List[str] = []

    failed = 0
    total = 0
    seam_counts: Dict[str, Any] = {}

    if results_path.exists():
        try:
            payload = load_json(results_path)
            summary = payload.get("summary", {})
            if not isinstance(summary, dict):
                summary = {}
            failed = int(summary.get("failed", 0))
            total = int(summary.get("total", 0))
            seam_counts = summary.get("seam_counts", {})
            if not isinstance(seam_counts, dict):
                seam_counts = {}
        except Exception as exc:  # noqa: BLE001
            errors.append(f"invalid phase9i results artifact: {exc}")
    else:
        errors.append(f"missing required artifact: {results_path}")

    if failed > max_failed_scenarios:
        errors.append(
            f"phase9i failed scenarios {failed} exceeds max {max_failed_scenarios}"
        )
    if total <= 0:
        errors.append("phase9i total scenarios must be > 0")

    missing_seams: List[str] = []
    for seam in required_seams:
        count = seam_counts.get(seam, 0)
        try:
            if int(count) <= 0:
                missing_seams.append(seam)
        except Exception:
            missing_seams.append(seam)
    if missing_seams:
        errors.append(f"phase9i missing seam coverage for: {', '.join(missing_seams)}")

    status = "pass" if not errors else "fail"
    row = {
        "id": "phase9i_fault_matrix",
        "blocking": True,
        "status": status,
        "required": f"failed <= {max_failed_scenarios}, total > 0, required seams covered",
        "observed": f"failed={failed} total={total}",
        "evidence": str(results_path),
    }
    summary = {
        "results_path": str(results_path),
        "failed": failed,
        "total": total,
        "seam_counts": seam_counts,
    }
    return row, summary, errors


def evaluate_known_risk_register(
    register_path: Path,
    max_age_days: int,
    required_fields: List[str],
    today: date,
) -> Tuple[Dict[str, Any], List[str]]:
    errors: List[str] = []
    register_payload: Dict[str, Any] = {}
    last_updated = ""
    active_count = 0
    resolved_count = 0
    overdue_active_ids: List[str] = []

    if not register_path.exists():
        errors.append(f"missing known-risk register: {register_path}")
    else:
        try:
            register_payload = load_json(register_path)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"invalid known-risk register: {exc}")

    risks = register_payload.get("risks", []) if isinstance(register_payload, dict) else []
    if not isinstance(risks, list):
        risks = []
        errors.append("known-risk register risks field must be an array")

    try:
        last_updated_raw = register_payload.get("lastUpdated") if isinstance(register_payload, dict) else None
        last_updated_date = parse_iso_date(last_updated_raw, "lastUpdated")
        last_updated = last_updated_date.isoformat()
        age_days = (today - last_updated_date).days
        if age_days > max_age_days:
            errors.append(
                f"known-risk register is stale: lastUpdated={last_updated} age_days={age_days} > {max_age_days}"
            )
    except Exception as exc:  # noqa: BLE001
        errors.append(str(exc))

    for entry in risks:
        if not isinstance(entry, dict):
            errors.append("risk entry must be an object")
            continue

        risk_id = str(entry.get("id", "unknown"))
        status = str(entry.get("status", "active"))
        if status == "active":
            active_count += 1
            for field in required_fields:
                value = entry.get(field)
                if not isinstance(value, str) or not value.strip():
                    errors.append(f"active risk {risk_id} missing required field: {field}")

            target_raw = entry.get("targetDate")
            if isinstance(target_raw, str) and target_raw.strip():
                try:
                    target_date = parse_iso_date(target_raw, f"risk {risk_id} targetDate")
                    if target_date < today:
                        overdue_active_ids.append(risk_id)
                except Exception as exc:  # noqa: BLE001
                    errors.append(str(exc))
        else:
            resolved_count += 1

    if overdue_active_ids:
        errors.append(
            f"known-risk register has overdue active risks: {', '.join(overdue_active_ids)}"
        )

    summary = {
        "source_path": str(register_path),
        "version": register_payload.get("version", "") if isinstance(register_payload, dict) else "",
        "last_updated": last_updated,
        "max_age_days": max_age_days,
        "is_current": len(errors) == 0,
        "active_count": active_count,
        "resolved_count": resolved_count,
        "overdue_active_ids": overdue_active_ids,
        "validation_errors": errors,
        "risks": risks,
    }
    return summary, errors


def render_markdown(
    generated_at: str,
    commit: str,
    release_id: str,
    certification_status: str,
    gate_rows: List[Dict[str, Any]],
    blocking_failures: List[str],
    warnings: List[str],
    risk_summary: Dict[str, Any],
    thresholds: Dict[str, Any],
    output_dir: Path,
) -> str:
    lines: List[str] = []
    lines.append("# Phase 9J Release Certification")
    lines.append("")
    lines.append(f"Generated at: `{generated_at}`")
    lines.append(f"Git commit: `{commit}`")
    lines.append(f"Release candidate: `{release_id}`")
    lines.append(f"Certification status: `{certification_status}`")
    lines.append("")

    lines.append("## Gate Matrix")
    lines.append("")
    lines.append("| Gate | Blocking | Status | Required | Observed | Evidence |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for row in gate_rows:
        lines.append(
            "| {id} | {blocking} | {status} | {required} | {observed} | `{evidence}` |".format(
                id=row.get("id", ""),
                blocking="yes" if bool(row.get("blocking")) else "no",
                status=row.get("status", "unknown"),
                required=row.get("required", ""),
                observed=row.get("observed", ""),
                evidence=row.get("evidence", ""),
            )
        )
    lines.append("")

    lines.append("## Known-Risk Register")
    lines.append("")
    lines.append(f"Source: `{risk_summary.get('source_path', '')}`")
    lines.append(f"Last updated: `{risk_summary.get('last_updated', '')}`")
    lines.append(f"Current: `{risk_summary.get('is_current', False)}`")
    lines.append(f"Active risks: `{risk_summary.get('active_count', 0)}`")
    lines.append(f"Resolved/mitigated risks: `{risk_summary.get('resolved_count', 0)}`")
    overdue = risk_summary.get("overdue_active_ids", [])
    if isinstance(overdue, list) and overdue:
        lines.append(f"Overdue active risk IDs: `{', '.join(str(item) for item in overdue)}`")
    lines.append("")

    lines.append("## Certification Thresholds")
    lines.append("")
    lines.append(f"Threshold fixture version: `{thresholds.get('version', '')}`")
    lines.append("Blocking fail criteria:")
    lines.append("- Phase 5E confidence manifest missing or invalid")
    lines.append("- Phase 9H blocking sanitizer lane status not allowed")
    lines.append("- Phase 9I fault matrix has failures above threshold or missing seam coverage")
    lines.append("- Known-risk register stale, malformed, overdue, or missing owner/target date on active risks")
    lines.append("")

    lines.append("## Outcome")
    lines.append("")
    if blocking_failures:
        lines.append("Blocking failures:")
        for failure in blocking_failures:
            lines.append(f"- {failure}")
    else:
        lines.append("- No blocking failures.")

    if warnings:
        lines.append("")
        lines.append("Non-blocking warnings:")
        for warning in warnings:
            lines.append(f"- {warning}")

    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 9J release certification pack")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--output-dir", default="build/release_confidence/phase9j")
    parser.add_argument(
        "--thresholds-fixture",
        default="tests/fixtures/release/phase9j_certification_thresholds.json",
    )
    parser.add_argument(
        "--risk-register",
        default="tests/fixtures/release/phase9j_known_risks.json",
    )
    parser.add_argument("--phase5e-dir", default="build/release_confidence/phase5e")
    parser.add_argument("--phase9h-dir", default="build/release_confidence/phase9h")
    parser.add_argument("--phase9i-dir", default="build/release_confidence/phase9i")
    parser.add_argument("--release-id", default="rc-unknown")
    parser.add_argument("--allow-incomplete", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = resolve_path(repo_root, args.output_dir)

    thresholds_path = resolve_path(repo_root, args.thresholds_fixture)
    risk_register_path = resolve_path(repo_root, args.risk_register)
    phase5e_dir = resolve_path(repo_root, args.phase5e_dir)
    phase9h_dir = resolve_path(repo_root, args.phase9h_dir)
    phase9i_dir = resolve_path(repo_root, args.phase9i_dir)

    thresholds = load_json(thresholds_path)
    blocking = thresholds.get("blocking_requirements", {})
    non_blocking = thresholds.get("non_blocking_requirements", {})
    risk_rules = thresholds.get("risk_register", {})
    if not isinstance(blocking, dict):
        blocking = {}
    if not isinstance(non_blocking, dict):
        non_blocking = {}
    if not isinstance(risk_rules, dict):
        risk_rules = {}

    manifest_required = bool(blocking.get("phase5e_manifest_required", True))
    blocking_allowed = safe_list_strings(blocking.get("phase9h_blocking_lane_allowed")) or ["pass"]
    tsan_allowed = safe_list_strings(non_blocking.get("phase9h_tsan_allowed")) or ["pass", "skipped"]
    max_failed_scenarios = int(blocking.get("phase9i_max_failed_scenarios", 0))
    required_seams = safe_list_strings(blocking.get("phase9i_required_seams"))

    max_age_days = int(risk_rules.get("max_age_days", 14))
    required_risk_fields = safe_list_strings(risk_rules.get("active_required_fields")) or [
        "owner",
        "targetDate",
    ]

    now = datetime.now(timezone.utc)
    generated_at = now.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    today = now.date()
    commit = git_commit(repo_root)

    gate_rows: List[Dict[str, Any]] = []
    blocking_failures: List[str] = []
    warnings: List[str] = []

    phase5e_row, phase5e_summary, phase5e_errors = evaluate_phase5e(phase5e_dir, manifest_required)
    gate_rows.append(phase5e_row)
    blocking_failures.extend(phase5e_errors)

    phase9h_rows, phase9h_summary, phase9h_errors = evaluate_phase9h(
        phase9h_dir,
        blocking_allowed,
        tsan_allowed,
    )
    gate_rows.extend(phase9h_rows)
    blocking_failures.extend(phase9h_errors)
    for row in phase9h_rows:
        if not bool(row.get("blocking")) and row.get("status") != "pass":
            warnings.append(f"{row.get('id')}: observed {row.get('observed')}")

    phase9i_row, phase9i_summary, phase9i_errors = evaluate_phase9i(
        phase9i_dir,
        max_failed_scenarios,
        required_seams,
    )
    gate_rows.append(phase9i_row)
    blocking_failures.extend(phase9i_errors)

    risk_summary, risk_errors = evaluate_known_risk_register(
        risk_register_path,
        max_age_days,
        required_risk_fields,
        today,
    )
    if risk_errors:
        blocking_failures.extend(risk_errors)

    certification_status = "certified" if not blocking_failures else "incomplete"

    output_dir.mkdir(parents=True, exist_ok=True)

    gate_matrix_payload = {
        "version": "phase9j-release-certification-v1",
        "generated_at": generated_at,
        "commit": commit,
        "release_id": args.release_id,
        "thresholds_version": thresholds.get("version", ""),
        "gates": gate_rows,
        "blocking_failures": blocking_failures,
        "warnings": warnings,
    }
    risk_snapshot_payload = {
        "version": "phase9j-release-certification-v1",
        "generated_at": generated_at,
        "commit": commit,
        "release_id": args.release_id,
        **risk_summary,
    }
    summary_payload = {
        "version": "phase9j-release-certification-v1",
        "generated_at": generated_at,
        "commit": commit,
        "release_id": args.release_id,
        "status": certification_status,
        "thresholds_version": thresholds.get("version", ""),
        "blocking_failures": blocking_failures,
        "warnings": warnings,
        "gate_summary": {
            "total": len(gate_rows),
            "passed": sum(1 for row in gate_rows if row.get("status") == "pass"),
            "failed": sum(1 for row in gate_rows if row.get("status") != "pass"),
            "blocking_total": sum(1 for row in gate_rows if bool(row.get("blocking"))),
            "blocking_failed": sum(
                1
                for row in gate_rows
                if bool(row.get("blocking")) and row.get("status") != "pass"
            ),
        },
        "evidence": {
            "phase5e": phase5e_summary,
            "phase9h": phase9h_summary,
            "phase9i": phase9i_summary,
            "known_risks": {
                "source_path": risk_summary.get("source_path", ""),
                "last_updated": risk_summary.get("last_updated", ""),
                "active_count": risk_summary.get("active_count", 0),
                "overdue_active_ids": risk_summary.get("overdue_active_ids", []),
            },
        },
    }

    markdown = render_markdown(
        generated_at,
        commit,
        args.release_id,
        certification_status,
        gate_rows,
        blocking_failures,
        warnings,
        risk_summary,
        thresholds,
        output_dir,
    )

    write_json(output_dir / "release_gate_matrix.json", gate_matrix_payload)
    write_json(output_dir / "known_risk_register_snapshot.json", risk_snapshot_payload)
    write_json(output_dir / "certification_summary.json", summary_payload)
    (output_dir / "phase9j_release_certification.md").write_text(markdown, encoding="utf-8")

    manifest_payload = {
        "version": "phase9j-release-certification-v1",
        "generated_at": generated_at,
        "commit": commit,
        "release_id": args.release_id,
        "status": certification_status,
        "artifacts": [
            "certification_summary.json",
            "release_gate_matrix.json",
            "known_risk_register_snapshot.json",
            "phase9j_release_certification.md",
        ],
        "thresholds_fixture": str(thresholds_path),
        "known_risk_register": str(risk_register_path),
    }
    write_json(output_dir / "manifest.json", manifest_payload)

    print(f"phase9j-certification: generated artifacts in {output_dir}")

    if certification_status != "certified" and not args.allow_incomplete:
        for failure in blocking_failures:
            print(f"phase9j-certification: blocking failure: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
