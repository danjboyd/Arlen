#!/usr/bin/env python3
"""Generate Phase 10H HTTP parser performance confidence artifacts."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from statistics import median
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


def run_benchmark(
    benchmark_binary: Path,
    fixtures_dir: Path,
    iterations: int,
    warmup: int,
    backend: str,
) -> Dict[str, Any]:
    command = [
        str(benchmark_binary),
        "--fixtures-dir",
        str(fixtures_dir),
        "--backend",
        backend,
        "--iterations",
        str(iterations),
        "--warmup",
        str(warmup),
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            "http parse benchmark failed "
            f"(backend={backend}, rc={result.returncode}):\n{result.stdout}\n{result.stderr}"
        )

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"http parse benchmark output was not valid JSON for backend={backend}: {exc}\n{result.stdout}"
        ) from exc

    if not isinstance(payload, dict):
        raise RuntimeError(f"http parse benchmark output must be a JSON object for backend={backend}")
    fixtures = payload.get("fixtures")
    if not isinstance(fixtures, list) or len(fixtures) == 0:
        raise RuntimeError(f"http parse benchmark output missing fixtures for backend={backend}")
    return payload


def run_benchmark_rounds(
    benchmark_binary: Path,
    fixtures_dir: Path,
    iterations: int,
    warmup: int,
    backend: str,
    rounds: int,
) -> List[Dict[str, Any]]:
    return [
        run_benchmark(benchmark_binary, fixtures_dir, iterations, warmup, backend)
        for _ in range(rounds)
    ]


def median_number(values: List[float]) -> float:
    if not values:
        return 0.0
    return float(median(values))


def aggregate_backend_rounds(backend: str, rounds_payload: List[Dict[str, Any]]) -> Dict[str, Any]:
    fixtures_by_name: Dict[str, List[Dict[str, Any]]] = {}
    llhttp_version = "unknown"
    iteration_values: List[float] = []
    warmup_values: List[float] = []
    for payload in rounds_payload:
        raw_version = payload.get("llhttp_version")
        if isinstance(raw_version, str) and raw_version:
            llhttp_version = raw_version
        raw_iterations = payload.get("iterations")
        if isinstance(raw_iterations, (int, float)):
            iteration_values.append(float(raw_iterations))
        raw_warmup = payload.get("warmup")
        if isinstance(raw_warmup, (int, float)):
            warmup_values.append(float(raw_warmup))
        fixtures = payload.get("fixtures")
        if not isinstance(fixtures, list):
            continue
        for fixture in fixtures:
            if not isinstance(fixture, dict):
                continue
            name = fixture.get("fixture")
            if not isinstance(name, str) or not name:
                continue
            fixtures_by_name.setdefault(name, []).append(fixture)

    aggregated_fixtures: List[Dict[str, Any]] = []
    for fixture_name in sorted(fixtures_by_name.keys()):
        rows = fixtures_by_name[fixture_name]
        bytes_values = [
            float(row.get("bytes"))
            for row in rows
            if isinstance(row.get("bytes"), (int, float))
        ]
        parse_values: Dict[str, List[float]] = {
            "iterations": [],
            "avg_us": [],
            "p95_us": [],
            "ops_per_sec": [],
            "total_seconds": [],
        }
        for row in rows:
            parse = row.get("parse")
            if not isinstance(parse, dict):
                continue
            for key in parse_values.keys():
                value = parse.get(key)
                if isinstance(value, (int, float)):
                    parse_values[key].append(float(value))

        aggregated_parse: Dict[str, Any] = {}
        for key, values in parse_values.items():
            if key == "iterations":
                aggregated_parse[key] = int(round(median_number(values)))
            else:
                aggregated_parse[key] = median_number(values)

        aggregated_fixtures.append(
            {
                "fixture": fixture_name,
                "bytes": int(round(median_number(bytes_values))),
                "parse": aggregated_parse,
            }
        )

    return {
        "version": "phase10h-http-parse-benchmark-v1",
        "backend": backend,
        "llhttp_version": llhttp_version,
        "iterations": int(round(median_number(iteration_values))),
        "warmup": int(round(median_number(warmup_values))),
        "fixture_count": len(aggregated_fixtures),
        "fixtures": aggregated_fixtures,
        "aggregation": {
            "method": "median",
            "round_count": len(rounds_payload),
        },
    }


def fixture_index(payload: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    fixtures = payload.get("fixtures", [])
    index: Dict[str, Dict[str, Any]] = {}
    if not isinstance(fixtures, list):
        return index
    for raw in fixtures:
        if not isinstance(raw, dict):
            continue
        fixture = raw.get("fixture")
        if not isinstance(fixture, str) or not fixture:
            continue
        index[fixture] = raw
    return index


def parse_metric(entry: Dict[str, Any], field: str) -> float:
    parse_payload = entry.get("parse", {})
    if not isinstance(parse_payload, dict):
        return 0.0
    value = parse_payload.get(field, 0.0)
    if isinstance(value, (int, float)):
        return float(value)
    return 0.0


def safe_ratio(numerator: float, denominator: float) -> float:
    if denominator <= 0.0:
        return 0.0
    return numerator / denominator


def summarize_deltas(legacy: Dict[str, Any], llhttp: Dict[str, Any]) -> List[Dict[str, Any]]:
    legacy_fixtures = fixture_index(legacy)
    llhttp_fixtures = fixture_index(llhttp)

    fixture_names = sorted(set(legacy_fixtures.keys()) | set(llhttp_fixtures.keys()))
    rows: List[Dict[str, Any]] = []
    for fixture in fixture_names:
        base = legacy_fixtures.get(fixture)
        cand = llhttp_fixtures.get(fixture)
        if base is None or cand is None:
            rows.append(
                {
                    "fixture": fixture,
                    "status": "missing_fixture",
                    "parse_ops_ratio": 0.0,
                    "parse_p95_ratio": 0.0,
                }
            )
            continue

        legacy_ops = parse_metric(base, "ops_per_sec")
        llhttp_ops = parse_metric(cand, "ops_per_sec")
        legacy_p95 = parse_metric(base, "p95_us")
        llhttp_p95 = parse_metric(cand, "p95_us")

        rows.append(
            {
                "fixture": fixture,
                "status": "ok",
                "bytes": int(cand.get("bytes", 0)) if isinstance(cand.get("bytes"), (int, float)) else 0,
                "parse_ops_ratio": safe_ratio(llhttp_ops, legacy_ops),
                "parse_p95_ratio": safe_ratio(llhttp_p95, legacy_p95),
                "legacy_parse_ops_per_sec": legacy_ops,
                "llhttp_parse_ops_per_sec": llhttp_ops,
                "legacy_parse_p95_us": legacy_p95,
                "llhttp_parse_p95_us": llhttp_p95,
            }
        )
    return rows


def evaluate_thresholds(thresholds: Dict[str, Any], deltas: List[Dict[str, Any]]) -> Tuple[str, List[str], Dict[str, Any]]:
    parse_ops_ratio_min = float(thresholds.get("parse_ops_ratio_min", 0.0))
    parse_p95_ratio_max = float(thresholds.get("parse_p95_ratio_max", 999.0))
    small_request_bytes_max = int(thresholds.get("small_request_bytes_max", 0))
    small_parse_ops_ratio_min = float(thresholds.get("small_parse_ops_ratio_min", parse_ops_ratio_min))
    small_parse_p95_ratio_max = float(thresholds.get("small_parse_p95_ratio_max", parse_p95_ratio_max))
    large_request_bytes_min = int(thresholds.get("large_request_bytes_min", 0))
    large_parse_ops_ratio_min = float(thresholds.get("large_parse_ops_ratio_min", parse_ops_ratio_min))
    large_parse_p95_ratio_max = float(thresholds.get("large_parse_p95_ratio_max", parse_p95_ratio_max))
    parse_expected_improvement_ratio_min = float(
        thresholds.get("parse_expected_improvement_ratio_min", 1.0)
    )
    parse_expected_improvement_fixture_count = int(
        thresholds.get("parse_expected_improvement_fixture_count", 0)
    )

    violations: List[str] = []
    improvement_count = 0
    small_fixture_count = 0
    large_fixture_count = 0
    for row in deltas:
        fixture = str(row.get("fixture", "unknown"))
        if row.get("status") != "ok":
            violations.append(f"fixture '{fixture}' missing in one backend result")
            continue

        parse_ops_ratio = float(row.get("parse_ops_ratio", 0.0))
        parse_p95_ratio = float(row.get("parse_p95_ratio", 0.0))
        fixture_bytes = int(row.get("bytes", 0))

        if parse_ops_ratio >= parse_expected_improvement_ratio_min:
            improvement_count += 1
        if parse_ops_ratio < parse_ops_ratio_min:
            violations.append(
                f"fixture '{fixture}' parse ops ratio {parse_ops_ratio:.3f} < {parse_ops_ratio_min:.3f}"
            )
        if parse_p95_ratio > parse_p95_ratio_max:
            violations.append(
                f"fixture '{fixture}' parse p95 ratio {parse_p95_ratio:.3f} > {parse_p95_ratio_max:.3f}"
            )

        if small_request_bytes_max > 0 and fixture_bytes <= small_request_bytes_max:
            small_fixture_count += 1
            if parse_ops_ratio < small_parse_ops_ratio_min:
                violations.append(
                    f"small fixture '{fixture}' parse ops ratio {parse_ops_ratio:.3f} < {small_parse_ops_ratio_min:.3f}"
                )
            if parse_p95_ratio > small_parse_p95_ratio_max:
                violations.append(
                    f"small fixture '{fixture}' parse p95 ratio {parse_p95_ratio:.3f} > {small_parse_p95_ratio_max:.3f}"
                )

        if large_request_bytes_min > 0 and fixture_bytes >= large_request_bytes_min:
            large_fixture_count += 1
            if parse_ops_ratio < large_parse_ops_ratio_min:
                violations.append(
                    f"large fixture '{fixture}' parse ops ratio {parse_ops_ratio:.3f} < {large_parse_ops_ratio_min:.3f}"
                )
            if parse_p95_ratio > large_parse_p95_ratio_max:
                violations.append(
                    f"large fixture '{fixture}' parse p95 ratio {parse_p95_ratio:.3f} > {large_parse_p95_ratio_max:.3f}"
                )

    if improvement_count < parse_expected_improvement_fixture_count:
        violations.append(
            "parse expected-improvement requirement not met: "
            f"{improvement_count} fixtures >= {parse_expected_improvement_ratio_min:.3f}, "
            f"required {parse_expected_improvement_fixture_count}"
        )

    policy_snapshot = {
        "parse_ops_ratio_min": parse_ops_ratio_min,
        "parse_p95_ratio_max": parse_p95_ratio_max,
        "parse_expected_improvement_ratio_min": parse_expected_improvement_ratio_min,
        "parse_expected_improvement_fixture_count": parse_expected_improvement_fixture_count,
        "parse_improvement_count_observed": improvement_count,
        "small_request_bytes_max": small_request_bytes_max,
        "small_fixture_count_observed": small_fixture_count,
        "small_parse_ops_ratio_min": small_parse_ops_ratio_min,
        "small_parse_p95_ratio_max": small_parse_p95_ratio_max,
        "large_request_bytes_min": large_request_bytes_min,
        "large_fixture_count_observed": large_fixture_count,
        "large_parse_ops_ratio_min": large_parse_ops_ratio_min,
        "large_parse_p95_ratio_max": large_parse_p95_ratio_max,
    }
    return ("pass" if not violations else "fail", violations, policy_snapshot)


def render_markdown(
    generated_at: str,
    commit_sha: str,
    iterations: int,
    warmup: int,
    rounds: int,
    status: str,
    policy: Dict[str, Any],
    violations: List[str],
    deltas: List[Dict[str, Any]],
    output_dir: Path,
) -> str:
    lines: List[str] = []
    lines.append("# Phase 10H HTTP Parser Performance Confidence Summary")
    lines.append("")
    lines.append(f"Generated at: `{generated_at}`")
    lines.append(f"Git commit: `{commit_sha}`")
    lines.append(f"Status: `{status}`")
    lines.append(f"Iterations: `{iterations}`")
    lines.append(f"Warmup iterations: `{warmup}`")
    lines.append(f"Benchmark rounds: `{rounds}` (median aggregation)")
    lines.append("")
    lines.append("## Artifacts")
    lines.append("")
    lines.append("- `http_parser_baseline_legacy.json`")
    lines.append("- `http_parser_candidate_llhttp.json`")
    lines.append("- `http_parser_delta_summary.json`")
    lines.append("- `phase10h_http_parse_performance.md`")
    lines.append("- `manifest.json`")
    lines.append("")
    lines.append("## Threshold Policy")
    lines.append("")
    lines.append(f"- parse ops ratio min: `{policy.get('parse_ops_ratio_min', 0.0):.3f}`")
    lines.append(f"- parse p95 ratio max: `{policy.get('parse_p95_ratio_max', 0.0):.3f}`")
    lines.append(
        f"- small fixture policy: bytes <= `{int(policy.get('small_request_bytes_max', 0))}`, "
        f"ops >= `{policy.get('small_parse_ops_ratio_min', 0.0):.3f}`, "
        f"p95 <= `{policy.get('small_parse_p95_ratio_max', 0.0):.3f}` "
        f"(observed `{int(policy.get('small_fixture_count_observed', 0))}` fixtures)"
    )
    lines.append(
        f"- large fixture policy: bytes >= `{int(policy.get('large_request_bytes_min', 0))}`, "
        f"ops >= `{policy.get('large_parse_ops_ratio_min', 0.0):.3f}`, "
        f"p95 <= `{policy.get('large_parse_p95_ratio_max', 0.0):.3f}` "
        f"(observed `{int(policy.get('large_fixture_count_observed', 0))}` fixtures)"
    )
    lines.append(
        "- parse expected improvement requirement: "
        f"`{policy.get('parse_expected_improvement_fixture_count', 0)}` fixtures at or above "
        f"`{policy.get('parse_expected_improvement_ratio_min', 0.0):.3f}` "
        f"(observed `{policy.get('parse_improvement_count_observed', 0)}`)"
    )
    lines.append("")
    lines.append("## Backend Delta Table (llhttp / legacy)")
    lines.append("")
    lines.append("| Fixture | Bytes | Parse ops ratio | Parse p95 ratio |")
    lines.append("| --- | --- | --- | --- |")
    for row in deltas:
        fixture = row.get("fixture", "unknown")
        fixture_bytes = int(row.get("bytes", 0))
        if row.get("status") != "ok":
            lines.append(f"| {fixture} | {fixture_bytes} | n/a | n/a |")
            continue
        lines.append(
            f"| {fixture} | {fixture_bytes} | {float(row.get('parse_ops_ratio', 0.0)):.3f} | "
            f"{float(row.get('parse_p95_ratio', 0.0)):.3f} |"
        )
    lines.append("")
    lines.append("## Gate Result")
    lines.append("")
    if not violations:
        lines.append("- No threshold violations detected.")
    else:
        for violation in violations:
            lines.append(f"- {violation}")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 10H HTTP parser performance confidence artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--benchmark-binary", required=True)
    parser.add_argument("--fixtures-dir", required=True)
    parser.add_argument("--thresholds", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase10h")
    parser.add_argument("--iterations", type=int, default=1500)
    parser.add_argument("--warmup", type=int, default=200)
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument(
        "--allow-fail",
        action="store_true",
        help="Always exit 0, even when threshold checks fail (writes fail status in artifacts).",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    benchmark_binary = Path(args.benchmark_binary).resolve()
    fixtures_dir = Path(args.fixtures_dir).resolve()
    thresholds_path = Path(args.thresholds).resolve()
    output_dir = Path(args.output_dir).resolve()

    if not benchmark_binary.exists():
        raise SystemExit(f"benchmark binary not found: {benchmark_binary}")
    if not fixtures_dir.exists():
        raise SystemExit(f"fixtures dir not found: {fixtures_dir}")
    if not thresholds_path.exists():
        raise SystemExit(f"thresholds file not found: {thresholds_path}")
    if args.rounds < 1:
        raise SystemExit("--rounds must be >= 1")

    thresholds = load_json(thresholds_path)
    legacy_rounds = run_benchmark_rounds(
        benchmark_binary,
        fixtures_dir,
        args.iterations,
        args.warmup,
        "legacy",
        args.rounds,
    )
    llhttp_rounds = run_benchmark_rounds(
        benchmark_binary,
        fixtures_dir,
        args.iterations,
        args.warmup,
        "llhttp",
        args.rounds,
    )
    legacy = aggregate_backend_rounds("legacy", legacy_rounds)
    llhttp = aggregate_backend_rounds("llhttp", llhttp_rounds)

    deltas = summarize_deltas(legacy, llhttp)
    status, violations, policy_snapshot = evaluate_thresholds(thresholds, deltas)

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    commit_sha = git_commit(repo_root)
    output_dir.mkdir(parents=True, exist_ok=True)

    legacy_path = output_dir / "http_parser_baseline_legacy.json"
    llhttp_path = output_dir / "http_parser_candidate_llhttp.json"
    delta_path = output_dir / "http_parser_delta_summary.json"
    markdown_path = output_dir / "phase10h_http_parse_performance.md"
    manifest_path = output_dir / "manifest.json"

    write_json(legacy_path, legacy)
    write_json(llhttp_path, llhttp)

    delta_payload = {
        "version": "phase10h-http-parse-performance-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "status": status,
        "rounds": args.rounds,
        "thresholds_version": thresholds.get("version", ""),
        "policy": policy_snapshot,
        "violations": violations,
        "deltas": deltas,
    }
    write_json(delta_path, delta_payload)

    markdown = render_markdown(
        generated_at,
        commit_sha,
        args.iterations,
        args.warmup,
        args.rounds,
        status,
        policy_snapshot,
        violations,
        deltas,
        output_dir,
    )
    markdown_path.write_text(markdown, encoding="utf-8")

    manifest = {
        "version": "phase10h-http-parse-performance-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "status": status,
        "artifacts": [
            "http_parser_baseline_legacy.json",
            "http_parser_candidate_llhttp.json",
            "http_parser_delta_summary.json",
            "phase10h_http_parse_performance.md",
        ],
    }
    write_json(manifest_path, manifest)

    print(f"phase10h-http-parse-performance: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
