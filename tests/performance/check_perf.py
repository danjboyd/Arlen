#!/usr/bin/env python3
import argparse
import csv
import datetime as dt
import json
import os
import platform
import statistics
import sys
from pathlib import Path


DEFAULT_POLICY = {
    "latency_regression_ratio": 1.15,
    "throughput_floor_ratio": 0.75,
    "memory_growth_kb_max": 16384,
    "memory_growth_ratio": 1.5,
}


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def as_float(value, fallback=0.0):
    try:
        return float(value)
    except Exception:
        return float(fallback)


def as_int(value, fallback=0):
    try:
        return int(value)
    except Exception:
        return int(fallback)


def median(values):
    if not values:
        return 0.0
    return float(statistics.median(values))


def load_policy(path: Path):
    policy = dict(DEFAULT_POLICY)
    if path.exists():
        with path.open("r", encoding="utf-8") as f:
            loaded = json.load(f)
            if isinstance(loaded, dict):
                policy.update({k: loaded[k] for k in DEFAULT_POLICY.keys() if k in loaded})
    return policy


def load_runs(path: Path):
    scenarios = {}
    with path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            scenario = (row.get("scenario") or "").strip()
            if not scenario:
                continue
            scenarios.setdefault(scenario, []).append(
                {
                    "run": as_int(row.get("run"), 0),
                    "requests": as_int(row.get("requests"), 0),
                    "p50_ms": as_float(row.get("p50_ms"), 0),
                    "p95_ms": as_float(row.get("p95_ms"), 0),
                    "p99_ms": as_float(row.get("p99_ms"), 0),
                    "max_ms": as_float(row.get("max_ms"), 0),
                    "req_per_sec": as_float(row.get("req_per_sec"), 0),
                    "duration_s": as_float(row.get("duration_s"), 0),
                }
            )
    return scenarios


def aggregate_runs(scenarios):
    aggregated = {}
    for name, runs in scenarios.items():
        aggregated[name] = {
            "requests": max([r["requests"] for r in runs] or [0]),
            "repeats": len(runs),
            "p50_ms": median([r["p50_ms"] for r in runs]),
            "p95_ms": median([r["p95_ms"] for r in runs]),
            "p99_ms": median([r["p99_ms"] for r in runs]),
            "max_ms": median([r["max_ms"] for r in runs]),
            "req_per_sec": median([r["req_per_sec"] for r in runs]),
            "duration_s": median([r["duration_s"] for r in runs]),
            "runs": runs,
        }
    return aggregated


def write_summary_csv(path: Path, scenarios):
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            ["scenario", "requests", "repeats", "p50_ms", "p95_ms", "p99_ms", "max_ms", "req_per_sec"]
        )
        for scenario in sorted(scenarios.keys()):
            m = scenarios[scenario]
            writer.writerow(
                [
                    scenario,
                    m["requests"],
                    m["repeats"],
                    f'{m["p50_ms"]:.3f}',
                    f'{m["p95_ms"]:.3f}',
                    f'{m["p99_ms"]:.3f}',
                    f'{m["max_ms"]:.3f}',
                    f'{m["req_per_sec"]:.2f}',
                ]
            )


def normalize_baseline(data):
    if not isinstance(data, dict):
        return {"scenarios": {}, "memory": {"growth_kb": 0}}

    if "scenarios" in data and isinstance(data["scenarios"], dict):
        memory = data.get("memory", {}) if isinstance(data.get("memory"), dict) else {}
        growth_kb = as_int(memory.get("growth_kb"), as_int(data.get("memory_after_kb"), 0) - as_int(data.get("memory_before_kb"), 0))
        return {
            "scenarios": data["scenarios"],
            "memory": {"growth_kb": growth_kb},
            "raw": data,
        }

    # Legacy flat baseline compatibility.
    scenarios = {}
    for key, value in data.items():
        if not isinstance(key, str):
            continue
        if key.endswith("_p95_ms"):
            scenario = key[: -len("_p95_ms")]
            scenarios.setdefault(scenario, {})["p95_ms"] = as_float(value)
        elif key.endswith("_req_per_sec"):
            scenario = key[: -len("_req_per_sec")]
            scenarios.setdefault(scenario, {})["req_per_sec"] = as_float(value)

    growth_kb = as_int(data.get("memory_after_kb"), 0) - as_int(data.get("memory_before_kb"), 0)
    return {
        "scenarios": scenarios,
        "memory": {"growth_kb": growth_kb},
        "raw": data,
    }


def compare(report, baseline, policy):
    failures = []
    baseline_scenarios = baseline.get("scenarios", {})
    report_scenarios = report.get("scenarios", {})

    for scenario, base in sorted(baseline_scenarios.items()):
        if scenario not in report_scenarios:
            failures.append(f"missing scenario in report: {scenario}")
            continue
        current = report_scenarios[scenario]

        base_p95 = as_float(base.get("p95_ms"), 0)
        if base_p95 > 0:
            threshold = base_p95 * as_float(policy["latency_regression_ratio"], 1.15)
            if as_float(current.get("p95_ms"), 0) > threshold:
                failures.append(
                    f"{scenario}: p95 regression current={current['p95_ms']:.3f} threshold={threshold:.3f}"
                )

        base_reqps = as_float(base.get("req_per_sec"), 0)
        if base_reqps > 0:
            floor = base_reqps * as_float(policy["throughput_floor_ratio"], 0.85)
            if as_float(current.get("req_per_sec"), 0) < floor:
                failures.append(
                    f"{scenario}: throughput floor violated current={current['req_per_sec']:.2f} floor={floor:.2f}"
                )

    base_growth = as_int(baseline.get("memory", {}).get("growth_kb"), 0)
    current_growth = as_int(report.get("memory", {}).get("growth_kb"), 0)
    absolute_limit = as_int(policy["memory_growth_kb_max"], 16384)
    ratio_limit = int(base_growth * as_float(policy["memory_growth_ratio"], 1.5))
    allowed_growth = max(absolute_limit, ratio_limit)
    if current_growth > allowed_growth:
        failures.append(
            f"memory growth guardrail violated current={current_growth}KB allowed={allowed_growth}KB"
        )

    return failures


def write_baseline(path: Path, report, policy, existing_baseline):
    created = utc_now()
    if isinstance(existing_baseline, dict):
        metadata = existing_baseline.get("baseline_metadata", {})
        if isinstance(metadata, dict) and metadata.get("created_utc"):
            created = metadata.get("created_utc")

    baseline = {
        "schema_version": 2,
        "baseline_metadata": {
            "created_utc": created,
            "updated_utc": utc_now(),
            "update_policy": "Set ARLEN_PERF_UPDATE_BASELINE=1 (or --update-baseline) for intentional baseline refreshes.",
        },
        "policy": policy,
        "host": report.get("host", "127.0.0.1"),
        "port": report.get("port", 0),
        "timestamp_utc": report.get("timestamp_utc"),
        "repeats": report.get("repeats", 0),
        "scenarios": report.get("scenarios", {}),
        "memory": report.get("memory", {}),
        "machine": report.get("machine", {}),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(baseline, f, indent=2, sort_keys=True)
        f.write("\n")


def main():
    parser = argparse.ArgumentParser(description="Aggregate and validate Arlen perf runs")
    parser.add_argument("--runs-csv", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--summary-csv", required=True)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--policy", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--mem-before-kb", type=int, default=0)
    parser.add_argument("--mem-after-kb", type=int, default=0)
    parser.add_argument("--update-baseline", action="store_true")
    parser.add_argument("--skip-gate", action="store_true")
    args = parser.parse_args()

    update_baseline = args.update_baseline or os.environ.get("ARLEN_PERF_UPDATE_BASELINE", "0") == "1"

    policy = load_policy(Path(args.policy))
    scenarios_runs = load_runs(Path(args.runs_csv))
    scenarios = aggregate_runs(scenarios_runs)
    write_summary_csv(Path(args.summary_csv), scenarios)

    repeats = max([m["repeats"] for m in scenarios.values()] or [0])
    report = {
        "schema_version": 2,
        "timestamp_utc": utc_now(),
        "host": args.host,
        "port": args.port,
        "repeats": repeats,
        "scenarios": scenarios,
        "memory": {
            "before_kb": int(args.mem_before_kb),
            "after_kb": int(args.mem_after_kb),
            "growth_kb": int(args.mem_after_kb) - int(args.mem_before_kb),
        },
        "machine": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "cpu_count": os.cpu_count(),
        },
    }

    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with report_path.open("w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, sort_keys=True)
        f.write("\n")

    baseline_path = Path(args.baseline)
    existing_baseline = None
    normalized_baseline = None
    if baseline_path.exists():
        with baseline_path.open("r", encoding="utf-8") as f:
            existing_baseline = json.load(f)
        normalized_baseline = normalize_baseline(existing_baseline)

    if args.skip_gate:
        print("perf: gate skipped (fast mode)")
        if update_baseline:
            write_baseline(baseline_path, report, policy, existing_baseline)
            print(f"perf: baseline updated at {baseline_path}")
        return 0

    if normalized_baseline is None:
        write_baseline(baseline_path, report, policy, existing_baseline)
        print(f"perf: baseline created at {baseline_path}")
        return 0

    failures = compare(report, normalized_baseline, policy)
    if failures and not update_baseline:
        print("perf: regression detected")
        for failure in failures:
            print(f"  - {failure}")
        print("perf: to refresh baseline for intentional changes, set ARLEN_PERF_UPDATE_BASELINE=1")
        return 1

    if update_baseline:
        write_baseline(baseline_path, report, policy, existing_baseline)
        print(f"perf: baseline updated at {baseline_path}")
        return 0

    print("perf: gate passed")
    for scenario in sorted(report["scenarios"].keys()):
        metrics = report["scenarios"][scenario]
        print(
            f"  - {scenario}: p95={metrics['p95_ms']:.3f}ms req/s={metrics['req_per_sec']:.2f}"
        )
    print(f"  - memory growth: {report['memory']['growth_kb']}KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
