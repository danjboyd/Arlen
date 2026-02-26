#!/usr/bin/env python3
"""Generate Phase 10G dispatch performance confidence artifacts."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from statistics import median
from typing import Any, Dict, List


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


def run_benchmark(benchmark_binary: Path, mode: str, iterations: int, warmup: int) -> Dict[str, Any]:
    command = [
        str(benchmark_binary),
        "--mode",
        mode,
        "--iterations",
        str(iterations),
        "--warmup",
        str(warmup),
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            "dispatch benchmark failed "
            f"(mode={mode}, rc={result.returncode}):\n{result.stdout}\n{result.stderr}"
        )

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"dispatch benchmark output was not valid JSON for mode={mode}: {exc}\n{result.stdout}"
        ) from exc

    if not isinstance(payload, dict):
        raise RuntimeError(f"dispatch benchmark output must be a JSON object for mode={mode}")
    timing = payload.get("timing")
    if not isinstance(timing, dict):
        raise RuntimeError(f"dispatch benchmark missing timing payload for mode={mode}")
    return payload


def run_benchmark_rounds(
    benchmark_binary: Path,
    mode: str,
    iterations: int,
    warmup: int,
    rounds: int,
) -> List[Dict[str, Any]]:
    return [run_benchmark(benchmark_binary, mode, iterations, warmup) for _ in range(rounds)]


def median_number(values: List[float]) -> float:
    if not values:
        return 0.0
    return float(median(values))


def aggregate_rounds(mode: str, rounds_payload: List[Dict[str, Any]]) -> Dict[str, Any]:
    timing_keys = ("iterations", "avg_us", "p95_us", "ops_per_sec", "total_seconds")
    aggregate_timing: Dict[str, Any] = {}
    for key in timing_keys:
        raw_values: List[float] = []
        for payload in rounds_payload:
            timing = payload.get("timing")
            if not isinstance(timing, dict):
                continue
            value = timing.get(key)
            if isinstance(value, (int, float)):
                raw_values.append(float(value))
        if key == "iterations":
            aggregate_timing[key] = int(round(median_number(raw_values)))
        else:
            aggregate_timing[key] = median_number(raw_values)

    return {
        "version": "phase10g-dispatch-benchmark-v1",
        "mode": mode,
        "timing": aggregate_timing,
        "aggregation": {
            "method": "median",
            "round_count": len(rounds_payload),
        },
        "rounds": rounds_payload,
    }


def metric(timing_payload: Dict[str, Any], name: str) -> float:
    raw = timing_payload.get(name, 0.0)
    if isinstance(raw, (int, float)):
        return float(raw)
    return 0.0


def safe_ratio(numerator: float, denominator: float) -> float:
    if denominator <= 0.0:
        return 0.0
    return numerator / denominator


def evaluate_thresholds(
    thresholds: Dict[str, Any],
    selector: Dict[str, Any],
    cached: Dict[str, Any],
) -> Dict[str, Any]:
    selector_timing = selector.get("timing", {})
    cached_timing = cached.get("timing", {})

    selector_ops = metric(selector_timing, "ops_per_sec")
    cached_ops = metric(cached_timing, "ops_per_sec")
    selector_p95 = metric(selector_timing, "p95_us")
    cached_p95 = metric(cached_timing, "p95_us")

    ops_ratio = safe_ratio(cached_ops, selector_ops)
    p95_ratio = safe_ratio(cached_p95, selector_p95)

    ops_ratio_min = float(thresholds.get("ops_ratio_min", 0.0))
    p95_ratio_max = float(thresholds.get("p95_ratio_max", 999.0))

    violations: List[str] = []
    if ops_ratio < ops_ratio_min:
        violations.append(f"dispatch ops ratio {ops_ratio:.3f} < {ops_ratio_min:.3f}")
    if p95_ratio > p95_ratio_max:
        violations.append(f"dispatch p95 ratio {p95_ratio:.3f} > {p95_ratio_max:.3f}")

    return {
        "status": "pass" if not violations else "fail",
        "violations": violations,
        "policy": {
            "ops_ratio_min": ops_ratio_min,
            "p95_ratio_max": p95_ratio_max,
        },
        "delta": {
            "cached_imp_ops_per_sec": cached_ops,
            "selector_ops_per_sec": selector_ops,
            "ops_ratio": ops_ratio,
            "cached_imp_p95_us": cached_p95,
            "selector_p95_us": selector_p95,
            "p95_ratio": p95_ratio,
        },
    }


def render_markdown(
    generated_at: str,
    commit_sha: str,
    iterations: int,
    warmup: int,
    rounds: int,
    threshold_eval: Dict[str, Any],
    output_dir: Path,
) -> str:
    status = threshold_eval["status"]
    policy = threshold_eval["policy"]
    delta = threshold_eval["delta"]
    violations = threshold_eval["violations"]

    lines: List[str] = []
    lines.append("# Phase 10G Dispatch Performance Confidence Summary")
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
    lines.append("- `dispatch_baseline_selector.json`")
    lines.append("- `dispatch_candidate_cached_imp.json`")
    lines.append("- `dispatch_delta_summary.json`")
    lines.append("- `phase10g_dispatch_performance.md`")
    lines.append("- `manifest.json`")
    lines.append("")
    lines.append("## Threshold Policy")
    lines.append("")
    lines.append(f"- ops ratio min: `{policy.get('ops_ratio_min', 0.0):.3f}`")
    lines.append(f"- p95 ratio max: `{policy.get('p95_ratio_max', 0.0):.3f}`")
    lines.append("")
    lines.append("## Delta")
    lines.append("")
    lines.append(f"- selector ops/sec: `{delta.get('selector_ops_per_sec', 0.0):.3f}`")
    lines.append(f"- cached_imp ops/sec: `{delta.get('cached_imp_ops_per_sec', 0.0):.3f}`")
    lines.append(f"- ops ratio (cached_imp/selector): `{delta.get('ops_ratio', 0.0):.3f}`")
    lines.append(f"- selector p95 us: `{delta.get('selector_p95_us', 0.0):.3f}`")
    lines.append(f"- cached_imp p95 us: `{delta.get('cached_imp_p95_us', 0.0):.3f}`")
    lines.append(f"- p95 ratio (cached_imp/selector): `{delta.get('p95_ratio', 0.0):.3f}`")
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
    parser = argparse.ArgumentParser(description="Generate Phase 10G dispatch performance confidence artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--benchmark-binary", required=True)
    parser.add_argument("--thresholds", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase10g")
    parser.add_argument("--iterations", type=int, default=50000)
    parser.add_argument("--warmup", type=int, default=5000)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument(
        "--allow-fail",
        action="store_true",
        help="Always exit 0, even when threshold checks fail (writes fail status in artifacts).",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    benchmark_binary = Path(args.benchmark_binary).resolve()
    thresholds_path = Path(args.thresholds).resolve()
    output_dir = Path(args.output_dir).resolve()

    if not benchmark_binary.exists():
        raise SystemExit(f"benchmark binary not found: {benchmark_binary}")
    if not thresholds_path.exists():
        raise SystemExit(f"thresholds file not found: {thresholds_path}")
    if args.rounds < 1:
        raise SystemExit("--rounds must be >= 1")

    thresholds = load_json(thresholds_path)
    selector_rounds = run_benchmark_rounds(
        benchmark_binary,
        "selector",
        args.iterations,
        args.warmup,
        args.rounds,
    )
    cached_rounds = run_benchmark_rounds(
        benchmark_binary,
        "cached_imp",
        args.iterations,
        args.warmup,
        args.rounds,
    )
    selector = aggregate_rounds("selector", selector_rounds)
    cached = aggregate_rounds("cached_imp", cached_rounds)
    threshold_eval = evaluate_thresholds(thresholds, selector, cached)

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    commit_sha = git_commit(repo_root)
    output_dir.mkdir(parents=True, exist_ok=True)

    selector_path = output_dir / "dispatch_baseline_selector.json"
    cached_path = output_dir / "dispatch_candidate_cached_imp.json"
    delta_path = output_dir / "dispatch_delta_summary.json"
    markdown_path = output_dir / "phase10g_dispatch_performance.md"
    manifest_path = output_dir / "manifest.json"

    write_json(selector_path, selector)
    write_json(cached_path, cached)

    delta_payload = {
        "version": "phase10g-dispatch-performance-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "status": threshold_eval["status"],
        "rounds": args.rounds,
        "thresholds_version": thresholds.get("version", ""),
        "policy": threshold_eval["policy"],
        "violations": threshold_eval["violations"],
        "delta": threshold_eval["delta"],
    }
    write_json(delta_path, delta_payload)

    markdown = render_markdown(
        generated_at,
        commit_sha,
        args.iterations,
        args.warmup,
        args.rounds,
        threshold_eval,
        output_dir,
    )
    markdown_path.write_text(markdown, encoding="utf-8")

    manifest = {
        "version": "phase10g-dispatch-performance-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "status": threshold_eval["status"],
        "artifacts": [
            "dispatch_baseline_selector.json",
            "dispatch_candidate_cached_imp.json",
            "dispatch_delta_summary.json",
            "phase10g_dispatch_performance.md",
        ],
    }
    write_json(manifest_path, manifest)

    print(f"phase10g-dispatch-performance: generated artifacts in {output_dir} (status={threshold_eval['status']})")
    if threshold_eval["status"] != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
