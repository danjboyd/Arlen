#!/usr/bin/env python3
"""Generate Phase 10L route-matcher investigation artifacts."""

from __future__ import annotations

import argparse
import json
import shutil
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


def median_number(values: List[float]) -> float:
    if not values:
        return 0.0
    return float(median(values))


def run_benchmark(
    benchmark_binary: Path,
    route_count: int,
    iterations: int,
    warmup: int,
) -> Dict[str, Any]:
    command = [
        str(benchmark_binary),
        "--route-count",
        str(route_count),
        "--iterations",
        str(iterations),
        "--warmup",
        str(warmup),
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            "route match benchmark failed "
            f"(rc={result.returncode}):\n{result.stdout}\n{result.stderr}"
        )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"route match benchmark output was not valid JSON: {exc}\n{result.stdout}"
        ) from exc
    if not isinstance(payload, dict):
        raise RuntimeError("route match benchmark output must be a JSON object")
    if payload.get("version") != "phase10l-route-match-benchmark-v1":
        raise RuntimeError("route match benchmark version mismatch")
    scenarios = payload.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        raise RuntimeError("route match benchmark missing scenarios")
    return payload


def run_benchmark_rounds(
    benchmark_binary: Path,
    route_count: int,
    iterations: int,
    warmup: int,
    rounds: int,
) -> List[Dict[str, Any]]:
    return [
        run_benchmark(benchmark_binary, route_count, iterations, warmup)
        for _ in range(rounds)
    ]


def aggregate_rounds(rounds_payload: List[Dict[str, Any]]) -> Dict[str, Any]:
    if not rounds_payload:
        raise ValueError("rounds_payload must not be empty")

    first = rounds_payload[0]
    scenario_names: List[str] = []
    scenario_meta: Dict[str, Dict[str, Any]] = {}
    for raw in first.get("scenarios", []):
        if not isinstance(raw, dict):
            continue
        name = str(raw.get("scenario", ""))
        if not name:
            continue
        scenario_names.append(name)
        scenario_meta[name] = {
            "scenario": name,
            "method": str(raw.get("method", "GET")),
            "path": str(raw.get("path", "/")),
            "expect_match": bool(raw.get("expect_match", True)),
        }

    aggregated_scenarios: List[Dict[str, Any]] = []
    for name in scenario_names:
        avg_samples: List[float] = []
        p95_samples: List[float] = []
        ops_samples: List[float] = []
        total_seconds_samples: List[float] = []
        iterations_samples: List[float] = []
        for payload in rounds_payload:
            scenarios = payload.get("scenarios")
            if not isinstance(scenarios, list):
                continue
            for raw in scenarios:
                if not isinstance(raw, dict):
                    continue
                if str(raw.get("scenario", "")) != name:
                    continue
                timing = raw.get("timing")
                if not isinstance(timing, dict):
                    continue
                for source, target in (
                    ("avg_us", avg_samples),
                    ("p95_us", p95_samples),
                    ("ops_per_sec", ops_samples),
                    ("total_seconds", total_seconds_samples),
                    ("iterations", iterations_samples),
                ):
                    value = timing.get(source)
                    if isinstance(value, (int, float)):
                        target.append(float(value))
                break

        aggregated_scenarios.append(
            {
                **scenario_meta.get(name, {"scenario": name}),
                "timing": {
                    "iterations": int(round(median_number(iterations_samples))),
                    "avg_us": median_number(avg_samples),
                    "p95_us": median_number(p95_samples),
                    "ops_per_sec": median_number(ops_samples),
                    "total_seconds": median_number(total_seconds_samples),
                },
                "aggregation": {
                    "method": "median",
                    "round_count": len(rounds_payload),
                },
            }
        )

    return {
        "version": "phase10l-route-match-benchmark-v1",
        "route_count_requested": int(first.get("route_count_requested", 0)),
        "route_count_actual": int(first.get("route_count_actual", 0)),
        "iterations": int(first.get("iterations", 0)),
        "warmup": int(first.get("warmup", 0)),
        "scenario_count": len(aggregated_scenarios),
        "scenarios": aggregated_scenarios,
        "aggregation": {
            "method": "median",
            "round_count": len(rounds_payload),
        },
        "rounds": rounds_payload,
    }


def evaluate_thresholds(
    thresholds: Dict[str, Any],
    aggregate_payload: Dict[str, Any],
) -> Tuple[str, List[str], Dict[str, Any]]:
    min_default_ops = float(thresholds.get("min_ops_per_sec_default", 0.0))
    max_default_p95 = float(thresholds.get("max_p95_us_default", 9999999.0))
    min_ops_by_scenario = thresholds.get("min_ops_per_sec_by_scenario", {})
    max_p95_by_scenario = thresholds.get("max_p95_us_by_scenario", {})
    if not isinstance(min_ops_by_scenario, dict):
        min_ops_by_scenario = {}
    if not isinstance(max_p95_by_scenario, dict):
        max_p95_by_scenario = {}

    violations: List[str] = []
    scenario_policies: List[Dict[str, Any]] = []
    for scenario in aggregate_payload.get("scenarios", []):
        if not isinstance(scenario, dict):
            continue
        name = str(scenario.get("scenario", ""))
        timing = scenario.get("timing", {})
        if not isinstance(timing, dict):
            timing = {}
        observed_ops = float(timing.get("ops_per_sec", 0.0))
        observed_p95 = float(timing.get("p95_us", 0.0))
        min_ops = float(min_ops_by_scenario.get(name, min_default_ops))
        max_p95 = float(max_p95_by_scenario.get(name, max_default_p95))
        if observed_ops < min_ops:
            violations.append(
                f"{name}: ops/sec {observed_ops:.3f} < min {min_ops:.3f}"
            )
        if observed_p95 > max_p95:
            violations.append(
                f"{name}: p95 {observed_p95:.3f}us > max {max_p95:.3f}us"
            )
        scenario_policies.append(
            {
                "scenario": name,
                "min_ops_per_sec": min_ops,
                "max_p95_us": max_p95,
                "observed_ops_per_sec": observed_ops,
                "observed_p95_us": observed_p95,
            }
        )

    status = "pass" if not violations else "fail"
    policy_snapshot = {
        "min_ops_per_sec_default": min_default_ops,
        "max_p95_us_default": max_default_p95,
        "min_ops_per_sec_by_scenario": min_ops_by_scenario,
        "max_p95_us_by_scenario": max_p95_by_scenario,
        "scenario_policy_eval": scenario_policies,
    }
    return status, violations, policy_snapshot


def capture_flamegraph_evidence(
    benchmark_binary: Path,
    output_dir: Path,
    route_count: int,
    iterations: int,
    warmup: int,
    frequency_hz: int,
) -> Dict[str, Any]:
    status: Dict[str, Any] = {
        "requested": True,
        "captured": False,
        "reason": "",
        "perf_data": "flamegraph_perf.data",
        "perf_script": "flamegraph_perf.script.txt",
    }

    perf_binary = shutil.which("perf")
    if perf_binary is None:
        status["reason"] = "perf_not_installed"
        return status

    perf_data = output_dir / "flamegraph_perf.data"
    perf_script = output_dir / "flamegraph_perf.script.txt"
    record_command = [
        perf_binary,
        "record",
        "-F",
        str(max(frequency_hz, 1)),
        "-g",
        "-o",
        str(perf_data),
        "--",
        str(benchmark_binary),
        "--route-count",
        str(route_count),
        "--iterations",
        str(iterations),
        "--warmup",
        str(warmup),
    ]
    record = subprocess.run(record_command, capture_output=True, text=True, check=False)
    status["record_command"] = record_command
    status["record_rc"] = record.returncode
    if record.returncode != 0:
        status["reason"] = "perf_record_failed"
        status["record_stdout_tail"] = record.stdout[-2000:]
        status["record_stderr_tail"] = record.stderr[-2000:]
        return status

    script_command = [perf_binary, "script", "-i", str(perf_data)]
    script_result = subprocess.run(script_command, capture_output=True, text=True, check=False)
    status["script_command"] = script_command
    status["script_rc"] = script_result.returncode
    if script_result.returncode != 0:
        status["reason"] = "perf_script_failed"
        status["script_stdout_tail"] = script_result.stdout[-2000:]
        status["script_stderr_tail"] = script_result.stderr[-2000:]
        return status

    perf_script.write_text(script_result.stdout, encoding="utf-8")
    status["captured"] = True
    status["reason"] = "captured"
    return status


def render_markdown(
    generated_at: str,
    commit_sha: str,
    route_count: int,
    iterations: int,
    warmup: int,
    rounds: int,
    status: str,
    violations: List[str],
    aggregate_payload: Dict[str, Any],
    flamegraph_status: Dict[str, Any],
    output_dir: Path,
) -> str:
    lines: List[str] = []
    lines.append("# Phase 10L Route Matcher Investigation Summary")
    lines.append("")
    lines.append(f"Generated at: `{generated_at}`")
    lines.append(f"Git commit: `{commit_sha}`")
    lines.append(f"Status: `{status}`")
    lines.append(f"Route count requested: `{route_count}`")
    lines.append(f"Iterations: `{iterations}`")
    lines.append(f"Warmup iterations: `{warmup}`")
    lines.append(f"Benchmark rounds: `{rounds}` (median aggregation)")
    lines.append("")
    lines.append("## Artifacts")
    lines.append("")
    lines.append("- `route_match_benchmark.json`")
    lines.append("- `route_match_threshold_eval.json`")
    lines.append("- `flamegraph_capture_status.json`")
    if flamegraph_status.get("captured"):
        lines.append("- `flamegraph_perf.data`")
        lines.append("- `flamegraph_perf.script.txt`")
    lines.append("- `phase10l_route_match_investigation.md`")
    lines.append("- `manifest.json`")
    lines.append("")
    lines.append("## Scenario Summary")
    lines.append("")
    for scenario in aggregate_payload.get("scenarios", []):
        if not isinstance(scenario, dict):
            continue
        name = str(scenario.get("scenario", "unknown"))
        timing = scenario.get("timing", {})
        if not isinstance(timing, dict):
            timing = {}
        lines.append(
            f"- `{name}`: ops/sec `{float(timing.get('ops_per_sec', 0.0)):.3f}`, "
            f"p95 `{float(timing.get('p95_us', 0.0)):.3f}us`"
        )
    lines.append("")
    lines.append("## Flamegraph Capture")
    lines.append("")
    lines.append(f"- requested: `{bool(flamegraph_status.get('requested', False))}`")
    lines.append(f"- captured: `{bool(flamegraph_status.get('captured', False))}`")
    lines.append(f"- reason: `{str(flamegraph_status.get('reason', 'unknown'))}`")
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
    parser = argparse.ArgumentParser(
        description="Generate Phase 10L route matcher investigation artifacts"
    )
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--benchmark-binary", required=True)
    parser.add_argument("--thresholds", required=True)
    parser.add_argument("--output-dir", default="build/release_confidence/phase10l")
    parser.add_argument("--route-count", type=int, default=12000)
    parser.add_argument("--iterations", type=int, default=15000)
    parser.add_argument("--warmup", type=int, default=1500)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--capture-flamegraph", action="store_true")
    parser.add_argument("--flamegraph-frequency", type=int, default=99)
    parser.add_argument("--flamegraph-iterations", type=int, default=15000)
    parser.add_argument("--flamegraph-warmup", type=int, default=1500)
    parser.add_argument(
        "--allow-fail",
        action="store_true",
        help="Always exit 0, even when threshold checks fail.",
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
    if args.route_count < 1:
        raise SystemExit("--route-count must be >= 1")

    thresholds = load_json(thresholds_path)
    benchmark_rounds = run_benchmark_rounds(
        benchmark_binary,
        args.route_count,
        args.iterations,
        args.warmup,
        args.rounds,
    )
    aggregate_payload = aggregate_rounds(benchmark_rounds)
    status, violations, policy_snapshot = evaluate_thresholds(thresholds, aggregate_payload)

    output_dir.mkdir(parents=True, exist_ok=True)
    flamegraph_status: Dict[str, Any]
    if args.capture_flamegraph:
        flamegraph_status = capture_flamegraph_evidence(
            benchmark_binary,
            output_dir,
            args.route_count,
            max(args.flamegraph_iterations, 1),
            max(args.flamegraph_warmup, 0),
            args.flamegraph_frequency,
        )
    else:
        flamegraph_status = {
            "requested": False,
            "captured": False,
            "reason": "disabled",
            "perf_data": "flamegraph_perf.data",
            "perf_script": "flamegraph_perf.script.txt",
        }

    generated_at = (
        datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    )
    commit_sha = git_commit(repo_root)

    threshold_eval_payload = {
        "version": "phase10l-route-match-investigation-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "status": status,
        "thresholds_version": thresholds.get("version", ""),
        "policy": policy_snapshot,
        "violations": violations,
        "flamegraph": flamegraph_status,
    }

    benchmark_path = output_dir / "route_match_benchmark.json"
    threshold_eval_path = output_dir / "route_match_threshold_eval.json"
    flamegraph_status_path = output_dir / "flamegraph_capture_status.json"
    markdown_path = output_dir / "phase10l_route_match_investigation.md"
    manifest_path = output_dir / "manifest.json"

    write_json(benchmark_path, aggregate_payload)
    write_json(threshold_eval_path, threshold_eval_payload)
    write_json(flamegraph_status_path, flamegraph_status)

    markdown = render_markdown(
        generated_at,
        commit_sha,
        args.route_count,
        args.iterations,
        args.warmup,
        args.rounds,
        status,
        violations,
        aggregate_payload,
        flamegraph_status,
        output_dir,
    )
    markdown_path.write_text(markdown, encoding="utf-8")

    artifacts = [
        "route_match_benchmark.json",
        "route_match_threshold_eval.json",
        "flamegraph_capture_status.json",
        "phase10l_route_match_investigation.md",
    ]
    if flamegraph_status.get("captured"):
        artifacts.append("flamegraph_perf.data")
        artifacts.append("flamegraph_perf.script.txt")

    manifest = {
        "version": "phase10l-route-match-investigation-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "status": status,
        "artifacts": artifacts,
    }
    write_json(manifest_path, manifest)

    print(
        "phase10l-route-match-investigation: generated artifacts "
        f"in {output_dir} (status={status})"
    )
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
