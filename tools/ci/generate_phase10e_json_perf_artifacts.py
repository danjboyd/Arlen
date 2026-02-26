#!/usr/bin/env python3
"""Run Phase 10E JSON backend benchmarks and generate confidence artifacts."""

from __future__ import annotations

import argparse
import json
import os
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
    env = os.environ.copy()
    env["ARLEN_JSON_BACKEND"] = backend
    command = [
        str(benchmark_binary),
        "--fixtures-dir",
        str(fixtures_dir),
        "--iterations",
        str(iterations),
        "--warmup",
        str(warmup),
    ]
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "benchmark command failed "
            f"(backend={backend}, rc={result.returncode}):\n{result.stdout}\n{result.stderr}"
        )

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"benchmark output was not valid JSON for backend={backend}: {exc}\n{result.stdout}"
        ) from exc

    if not isinstance(payload, dict):
        raise RuntimeError(f"benchmark output must be a JSON object for backend={backend}")
    fixtures = payload.get("fixtures")
    if not isinstance(fixtures, list) or len(fixtures) == 0:
        raise RuntimeError(f"benchmark output missing fixtures for backend={backend}")
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
    yyjson_version = "unknown"
    iteration_values: List[float] = []
    warmup_values: List[float] = []
    for payload in rounds_payload:
        raw_version = payload.get("yyjson_version")
        if isinstance(raw_version, str) and raw_version:
            yyjson_version = raw_version
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
        mode_values: Dict[str, Dict[str, List[float]]] = {
            "decode": {
                "iterations": [],
                "avg_us": [],
                "p95_us": [],
                "ops_per_sec": [],
                "total_seconds": [],
            },
            "encode": {
                "iterations": [],
                "avg_us": [],
                "p95_us": [],
                "ops_per_sec": [],
                "total_seconds": [],
            },
        }
        for row in rows:
            for mode in ("decode", "encode"):
                mode_payload = row.get(mode)
                if not isinstance(mode_payload, dict):
                    continue
                for key in mode_values[mode].keys():
                    value = mode_payload.get(key)
                    if isinstance(value, (int, float)):
                        mode_values[mode][key].append(float(value))

        aggregated_decode: Dict[str, Any] = {}
        aggregated_encode: Dict[str, Any] = {}
        for mode, target in (("decode", aggregated_decode), ("encode", aggregated_encode)):
            for key, values in mode_values[mode].items():
                if key == "iterations":
                    target[key] = int(round(median_number(values)))
                else:
                    target[key] = median_number(values)

        aggregated_fixtures.append(
            {
                "fixture": fixture_name,
                "bytes": int(round(median_number(bytes_values))),
                "decode": aggregated_decode,
                "encode": aggregated_encode,
            }
        )

    return {
        "version": "phase10e-json-benchmark-v1",
        "backend": backend,
        "yyjson_version": yyjson_version,
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


def metric_value(entry: Dict[str, Any], mode: str, field: str) -> float:
    mode_payload = entry.get(mode, {})
    if not isinstance(mode_payload, dict):
        return 0.0
    value = mode_payload.get(field, 0.0)
    if isinstance(value, (int, float)):
        return float(value)
    return 0.0


def safe_ratio(numerator: float, denominator: float) -> float:
    if denominator <= 0.0:
        return 0.0
    return numerator / denominator


def summarize_deltas(foundation: Dict[str, Any], yyjson: Dict[str, Any]) -> List[Dict[str, Any]]:
    foundation_fixtures = fixture_index(foundation)
    yyjson_fixtures = fixture_index(yyjson)

    fixture_names = sorted(set(foundation_fixtures.keys()) | set(yyjson_fixtures.keys()))
    rows: List[Dict[str, Any]] = []
    for fixture in fixture_names:
        base = foundation_fixtures.get(fixture)
        cand = yyjson_fixtures.get(fixture)
        if base is None or cand is None:
            rows.append(
                {
                    "fixture": fixture,
                    "status": "missing_fixture",
                    "decode_ops_ratio": 0.0,
                    "encode_ops_ratio": 0.0,
                    "decode_p95_ratio": 0.0,
                    "encode_p95_ratio": 0.0,
                }
            )
            continue

        base_decode_ops = metric_value(base, "decode", "ops_per_sec")
        yy_decode_ops = metric_value(cand, "decode", "ops_per_sec")
        base_encode_ops = metric_value(base, "encode", "ops_per_sec")
        yy_encode_ops = metric_value(cand, "encode", "ops_per_sec")

        base_decode_p95 = metric_value(base, "decode", "p95_us")
        yy_decode_p95 = metric_value(cand, "decode", "p95_us")
        base_encode_p95 = metric_value(base, "encode", "p95_us")
        yy_encode_p95 = metric_value(cand, "encode", "p95_us")

        rows.append(
            {
                "fixture": fixture,
                "status": "ok",
                "bytes": int(cand.get("bytes", 0)) if isinstance(cand.get("bytes"), (int, float)) else 0,
                "decode_ops_ratio": safe_ratio(yy_decode_ops, base_decode_ops),
                "encode_ops_ratio": safe_ratio(yy_encode_ops, base_encode_ops),
                "decode_p95_ratio": safe_ratio(yy_decode_p95, base_decode_p95),
                "encode_p95_ratio": safe_ratio(yy_encode_p95, base_encode_p95),
                "foundation_decode_ops_per_sec": base_decode_ops,
                "yyjson_decode_ops_per_sec": yy_decode_ops,
                "foundation_encode_ops_per_sec": base_encode_ops,
                "yyjson_encode_ops_per_sec": yy_encode_ops,
                "foundation_decode_p95_us": base_decode_p95,
                "yyjson_decode_p95_us": yy_decode_p95,
                "foundation_encode_p95_us": base_encode_p95,
                "yyjson_encode_p95_us": yy_encode_p95,
            }
        )
    return rows


def evaluate_thresholds(
    thresholds: Dict[str, Any],
    deltas: List[Dict[str, Any]],
) -> Tuple[str, List[str], Dict[str, Any]]:
    decode_ops_ratio_min = float(thresholds.get("decode_ops_ratio_min", 0.0))
    encode_ops_ratio_min = float(thresholds.get("encode_ops_ratio_min", 0.0))
    decode_p95_ratio_max = float(thresholds.get("decode_p95_ratio_max", 999.0))
    encode_p95_ratio_max = float(thresholds.get("encode_p95_ratio_max", 999.0))
    decode_expected_improvement_ratio_min = float(
        thresholds.get("decode_expected_improvement_ratio_min", 1.0)
    )
    decode_expected_improvement_fixture_count = int(
        thresholds.get("decode_expected_improvement_fixture_count", 0)
    )

    violations: List[str] = []
    decode_improvement_count = 0
    for row in deltas:
        fixture = str(row.get("fixture", "unknown"))
        status = row.get("status")
        if status != "ok":
            violations.append(f"fixture '{fixture}' missing in one backend result")
            continue

        decode_ops_ratio = float(row.get("decode_ops_ratio", 0.0))
        encode_ops_ratio = float(row.get("encode_ops_ratio", 0.0))
        decode_p95_ratio = float(row.get("decode_p95_ratio", 0.0))
        encode_p95_ratio = float(row.get("encode_p95_ratio", 0.0))

        if decode_ops_ratio >= decode_expected_improvement_ratio_min:
            decode_improvement_count += 1
        if decode_ops_ratio < decode_ops_ratio_min:
            violations.append(
                f"fixture '{fixture}' decode ops ratio {decode_ops_ratio:.3f} < {decode_ops_ratio_min:.3f}"
            )
        if encode_ops_ratio < encode_ops_ratio_min:
            violations.append(
                f"fixture '{fixture}' encode ops ratio {encode_ops_ratio:.3f} < {encode_ops_ratio_min:.3f}"
            )
        if decode_p95_ratio > decode_p95_ratio_max:
            violations.append(
                f"fixture '{fixture}' decode p95 ratio {decode_p95_ratio:.3f} > {decode_p95_ratio_max:.3f}"
            )
        if encode_p95_ratio > encode_p95_ratio_max:
            violations.append(
                f"fixture '{fixture}' encode p95 ratio {encode_p95_ratio:.3f} > {encode_p95_ratio_max:.3f}"
            )

    if decode_improvement_count < decode_expected_improvement_fixture_count:
        violations.append(
            "decode expected-improvement requirement not met: "
            f"{decode_improvement_count} fixtures >= {decode_expected_improvement_ratio_min:.3f}, "
            f"required {decode_expected_improvement_fixture_count}"
        )

    status = "pass" if len(violations) == 0 else "fail"
    policy_snapshot = {
        "decode_ops_ratio_min": decode_ops_ratio_min,
        "encode_ops_ratio_min": encode_ops_ratio_min,
        "decode_p95_ratio_max": decode_p95_ratio_max,
        "encode_p95_ratio_max": encode_p95_ratio_max,
        "decode_expected_improvement_ratio_min": decode_expected_improvement_ratio_min,
        "decode_expected_improvement_fixture_count": decode_expected_improvement_fixture_count,
        "decode_improvement_count_observed": decode_improvement_count,
    }
    return status, violations, policy_snapshot


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
    lines.append("# Phase 10E JSON Performance Confidence Summary")
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
    lines.append("- `json_backend_baseline_foundation.json`")
    lines.append("- `json_backend_candidate_yyjson.json`")
    lines.append("- `json_backend_delta_summary.json`")
    lines.append("- `phase10e_json_performance.md`")
    lines.append("- `manifest.json`")
    lines.append("")
    lines.append("## Threshold Policy")
    lines.append("")
    lines.append(f"- decode ops ratio min: `{policy.get('decode_ops_ratio_min', 0.0):.3f}`")
    lines.append(f"- encode ops ratio min: `{policy.get('encode_ops_ratio_min', 0.0):.3f}`")
    lines.append(f"- decode p95 ratio max: `{policy.get('decode_p95_ratio_max', 0.0):.3f}`")
    lines.append(f"- encode p95 ratio max: `{policy.get('encode_p95_ratio_max', 0.0):.3f}`")
    lines.append(
        "- decode expected improvement requirement: "
        f"`{policy.get('decode_expected_improvement_fixture_count', 0)}` fixtures at or above "
        f"`{policy.get('decode_expected_improvement_ratio_min', 0.0):.3f}` "
        f"(observed `{policy.get('decode_improvement_count_observed', 0)}`)"
    )
    lines.append("")
    lines.append("## Backend Delta Table (yyjson / foundation)")
    lines.append("")
    lines.append("| Fixture | Decode ops ratio | Encode ops ratio | Decode p95 ratio | Encode p95 ratio |")
    lines.append("| --- | --- | --- | --- | --- |")
    for row in deltas:
        fixture = row.get("fixture", "unknown")
        if row.get("status") != "ok":
            lines.append(f"| {fixture} | n/a | n/a | n/a | n/a |")
            continue
        lines.append(
            f"| {fixture} | {float(row.get('decode_ops_ratio', 0.0)):.3f} | "
            f"{float(row.get('encode_ops_ratio', 0.0)):.3f} | "
            f"{float(row.get('decode_p95_ratio', 0.0)):.3f} | "
            f"{float(row.get('encode_p95_ratio', 0.0)):.3f} |"
        )
    lines.append("")
    lines.append("## Gate Result")
    lines.append("")
    if len(violations) == 0:
        lines.append("- No threshold violations detected.")
    else:
        for violation in violations:
            lines.append(f"- {violation}")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 10E JSON performance confidence artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--benchmark-binary", required=True)
    parser.add_argument("--fixtures-dir", required=True)
    parser.add_argument("--thresholds", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase10e")
    parser.add_argument("--iterations", type=int, default=1500)
    parser.add_argument("--warmup", type=int, default=200)
    parser.add_argument("--rounds", type=int, default=3)
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
    foundation_rounds = run_benchmark_rounds(
        benchmark_binary,
        fixtures_dir,
        args.iterations,
        args.warmup,
        "foundation",
        args.rounds,
    )
    yyjson_rounds = run_benchmark_rounds(
        benchmark_binary,
        fixtures_dir,
        args.iterations,
        args.warmup,
        "yyjson",
        args.rounds,
    )
    foundation = aggregate_backend_rounds("foundation", foundation_rounds)
    yyjson = aggregate_backend_rounds("yyjson", yyjson_rounds)

    deltas = summarize_deltas(foundation, yyjson)
    status, violations, policy_snapshot = evaluate_thresholds(thresholds, deltas)

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    commit_sha = git_commit(repo_root)
    output_dir.mkdir(parents=True, exist_ok=True)

    foundation_path = output_dir / "json_backend_baseline_foundation.json"
    yyjson_path = output_dir / "json_backend_candidate_yyjson.json"
    delta_path = output_dir / "json_backend_delta_summary.json"
    markdown_path = output_dir / "phase10e_json_performance.md"
    manifest_path = output_dir / "manifest.json"

    write_json(foundation_path, foundation)
    write_json(yyjson_path, yyjson)

    delta_payload = {
        "version": "phase10e-json-performance-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "status": status,
        "thresholds_version": thresholds.get("version", ""),
        "rounds": args.rounds,
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
        "version": "phase10e-json-performance-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "status": status,
        "iterations": args.iterations,
        "warmup": args.warmup,
        "rounds": args.rounds,
        "thresholds": str(thresholds_path),
        "artifacts": [
            foundation_path.name,
            yyjson_path.name,
            delta_path.name,
            markdown_path.name,
        ],
    }
    write_json(manifest_path, manifest)

    print(f"phase10e-json-performance: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
