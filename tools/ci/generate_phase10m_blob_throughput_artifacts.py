#!/usr/bin/env python3
"""Generate Phase 10M.9 large-body throughput artifacts."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple

VERSION = "phase10m-blob-throughput-v1"
THRESHOLDS_VERSION = "phase10m-blob-throughput-thresholds-v1"


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


def number(value: Any) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    return 0.0


def safe_ratio(numerator: float, denominator: float) -> float:
    if denominator <= 0.0:
        return 0.0
    return numerator / denominator


def scenario_metrics(report: Dict[str, Any], scenario: str) -> Dict[str, float]:
    scenarios = report.get("scenarios", {})
    if not isinstance(scenarios, dict):
        return {}
    row = scenarios.get(scenario, {})
    if not isinstance(row, dict):
        return {}
    return {
        "req_per_sec": number(row.get("req_per_sec")),
        "p95_ms": number(row.get("p95_ms")),
        "p50_ms": number(row.get("p50_ms")),
        "p99_ms": number(row.get("p99_ms")),
    }


def evaluate(
    report: Dict[str, Any],
    thresholds: Dict[str, Any],
) -> Tuple[str, List[str], Dict[str, Any]]:
    scenario_names = thresholds.get("scenario_names", {})
    if not isinstance(scenario_names, dict):
        scenario_names = {}
    legacy_name = str(scenario_names.get("legacy_e2e", "blob_legacy_string_e2e"))
    binary_name = str(scenario_names.get("binary_e2e", "blob_binary_e2e"))
    sendfile_name = str(scenario_names.get("binary_sendfile", "blob_binary_sendfile"))

    legacy = scenario_metrics(report, legacy_name)
    binary = scenario_metrics(report, binary_name)
    sendfile = scenario_metrics(report, sendfile_name)

    violations: List[str] = []
    if not legacy:
        violations.append(f"missing scenario metrics: {legacy_name}")
    if not binary:
        violations.append(f"missing scenario metrics: {binary_name}")
    if not sendfile:
        violations.append(f"missing scenario metrics: {sendfile_name}")

    binary_vs_legacy = thresholds.get("binary_vs_legacy", {})
    if not isinstance(binary_vs_legacy, dict):
        binary_vs_legacy = {}
    sendfile_vs_binary = thresholds.get("sendfile_vs_binary", {})
    if not isinstance(sendfile_vs_binary, dict):
        sendfile_vs_binary = {}

    binary_req_ratio = safe_ratio(binary.get("req_per_sec", 0.0), legacy.get("req_per_sec", 0.0))
    binary_p95_ratio = safe_ratio(binary.get("p95_ms", 0.0), legacy.get("p95_ms", 0.0))
    sendfile_req_ratio = safe_ratio(sendfile.get("req_per_sec", 0.0), binary.get("req_per_sec", 0.0))
    sendfile_p95_ratio = safe_ratio(sendfile.get("p95_ms", 0.0), binary.get("p95_ms", 0.0))

    min_binary_req_ratio = number(binary_vs_legacy.get("min_req_per_sec_ratio"))
    max_binary_p95_ratio = number(binary_vs_legacy.get("max_p95_ratio"))
    min_sendfile_req_ratio = number(sendfile_vs_binary.get("min_req_per_sec_ratio"))
    max_sendfile_p95_ratio = number(sendfile_vs_binary.get("max_p95_ratio"))

    if binary and legacy:
        if min_binary_req_ratio > 0.0 and binary_req_ratio < min_binary_req_ratio:
            violations.append(
                f"binary-vs-legacy throughput ratio {binary_req_ratio:.3f} < {min_binary_req_ratio:.3f}"
            )
        if max_binary_p95_ratio > 0.0 and binary_p95_ratio > max_binary_p95_ratio:
            violations.append(
                f"binary-vs-legacy p95 ratio {binary_p95_ratio:.3f} > {max_binary_p95_ratio:.3f}"
            )

    if sendfile and binary:
        if min_sendfile_req_ratio > 0.0 and sendfile_req_ratio < min_sendfile_req_ratio:
            violations.append(
                f"sendfile-vs-binary throughput ratio {sendfile_req_ratio:.3f} < {min_sendfile_req_ratio:.3f}"
            )
        if max_sendfile_p95_ratio > 0.0 and sendfile_p95_ratio > max_sendfile_p95_ratio:
            violations.append(
                f"sendfile-vs-binary p95 ratio {sendfile_p95_ratio:.3f} > {max_sendfile_p95_ratio:.3f}"
            )

    min_req_per_sec = thresholds.get("min_req_per_sec", {})
    if not isinstance(min_req_per_sec, dict):
        min_req_per_sec = {}
    max_p95_ms = thresholds.get("max_p95_ms", {})
    if not isinstance(max_p95_ms, dict):
        max_p95_ms = {}

    for scenario_name, floor_value in min_req_per_sec.items():
        scenario_name = str(scenario_name)
        floor = number(floor_value)
        observed = scenario_metrics(report, scenario_name).get("req_per_sec", 0.0)
        if floor > 0.0 and observed < floor:
            violations.append(
                f"{scenario_name} req/s {observed:.3f} < min {floor:.3f}"
            )

    for scenario_name, ceiling_value in max_p95_ms.items():
        scenario_name = str(scenario_name)
        ceiling = number(ceiling_value)
        observed = scenario_metrics(report, scenario_name).get("p95_ms", 0.0)
        if ceiling > 0.0 and observed > ceiling:
            violations.append(
                f"{scenario_name} p95 {observed:.3f}ms > max {ceiling:.3f}ms"
            )

    status = "pass" if not violations else "fail"
    ratios = {
        "binary_vs_legacy_req_per_sec_ratio": binary_req_ratio,
        "binary_vs_legacy_p95_ratio": binary_p95_ratio,
        "sendfile_vs_binary_req_per_sec_ratio": sendfile_req_ratio,
        "sendfile_vs_binary_p95_ratio": sendfile_p95_ratio,
    }
    metrics = {
        legacy_name: legacy,
        binary_name: binary,
        sendfile_name: sendfile,
    }
    return status, violations, {"ratios": ratios, "metrics": metrics}


def render_markdown(
    generated_at: str,
    commit: str,
    report: Dict[str, Any],
    status: str,
    violations: List[str],
    eval_payload: Dict[str, Any],
) -> str:
    metrics = eval_payload.get("metrics", {})
    ratios = eval_payload.get("ratios", {})
    lines: List[str] = []
    lines.append("# Phase 10M.9 Blob Throughput")
    lines.append("")
    lines.append(f"Generated at: `{generated_at}`")
    lines.append(f"Git commit: `{commit}`")
    lines.append(f"Perf profile: `{report.get('profile', '')}`")
    lines.append(f"Status: `{status}`")
    lines.append("")
    lines.append("| Scenario | req/s | p95 ms | p50 ms | p99 ms |")
    lines.append("| --- | ---: | ---: | ---: | ---: |")
    for scenario_name in sorted(metrics.keys()):
        row = metrics.get(scenario_name, {})
        if not isinstance(row, dict):
            row = {}
        lines.append(
            "| {name} | {req:.2f} | {p95:.3f} | {p50:.3f} | {p99:.3f} |".format(
                name=scenario_name,
                req=number(row.get("req_per_sec")),
                p95=number(row.get("p95_ms")),
                p50=number(row.get("p50_ms")),
                p99=number(row.get("p99_ms")),
            )
        )

    lines.append("")
    lines.append("## Ratio Checks")
    lines.append("")
    lines.append(
        f"- binary vs legacy req/s ratio: `{number(ratios.get('binary_vs_legacy_req_per_sec_ratio')):.3f}`"
    )
    lines.append(
        f"- binary vs legacy p95 ratio: `{number(ratios.get('binary_vs_legacy_p95_ratio')):.3f}`"
    )
    lines.append(
        f"- sendfile vs binary req/s ratio: `{number(ratios.get('sendfile_vs_binary_req_per_sec_ratio')):.3f}`"
    )
    lines.append(
        f"- sendfile vs binary p95 ratio: `{number(ratios.get('sendfile_vs_binary_p95_ratio')):.3f}`"
    )

    lines.append("")
    lines.append("## Violations")
    lines.append("")
    if violations:
        for violation in violations:
            lines.append(f"- {violation}")
    else:
        lines.append("- none")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 10M.9 blob throughput artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--report", required=True)
    parser.add_argument("--runs-csv", default="")
    parser.add_argument("--summary-csv", default="")
    parser.add_argument(
        "--thresholds",
        default="tests/fixtures/performance/phase10m_blob_throughput_thresholds.json",
    )
    parser.add_argument(
        "--output-dir",
        default="build/release_confidence/phase10m/blob_throughput",
    )
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    report_path = Path(args.report).resolve()
    thresholds_path = Path(args.thresholds).resolve()
    output_dir = Path(args.output_dir).resolve()

    report = load_json(report_path)
    thresholds = load_json(thresholds_path)
    if thresholds.get("version") != THRESHOLDS_VERSION:
        raise SystemExit("phase10m blob throughput thresholds version mismatch")

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    commit = git_commit(repo_root)

    status, violations, eval_payload = evaluate(report, thresholds)
    result_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": commit,
        "status": status,
        "thresholds": str(thresholds_path),
        "thresholds_version": thresholds.get("version", ""),
        "profile": report.get("profile", ""),
        "violations": violations,
        "evaluation": eval_payload,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    report_copy = output_dir / "phase10m_blob_perf_report.json"
    shutil.copyfile(report_path, report_copy)
    artifacts = [
        "phase10m_blob_perf_report.json",
        "phase10m_blob_throughput_eval.json",
        "phase10m_blob_throughput.md",
    ]

    if args.runs_csv:
        runs_path = Path(args.runs_csv).resolve()
        if runs_path.exists():
            shutil.copyfile(runs_path, output_dir / "phase10m_blob_perf_runs.csv")
            artifacts.append("phase10m_blob_perf_runs.csv")
    if args.summary_csv:
        summary_path = Path(args.summary_csv).resolve()
        if summary_path.exists():
            shutil.copyfile(summary_path, output_dir / "phase10m_blob_perf_summary.csv")
            artifacts.append("phase10m_blob_perf_summary.csv")

    write_json(output_dir / "phase10m_blob_throughput_eval.json", result_payload)
    markdown = render_markdown(generated_at, commit, report, status, violations, eval_payload)
    (output_dir / "phase10m_blob_throughput.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": commit,
        "status": status,
        "artifacts": sorted(artifacts),
    }
    write_json(output_dir / "manifest.json", manifest)

    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
