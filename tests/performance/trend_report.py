#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import statistics
from pathlib import Path


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
    cleaned = [as_float(v, 0.0) for v in values if v is not None]
    if not cleaned:
        return None
    return float(statistics.median(cleaned))


def percent_change(latest, baseline):
    if latest is None or baseline is None or baseline == 0:
        return None
    return ((latest - baseline) / baseline) * 100.0


def trend_state(metric_name, latest, baseline):
    if latest is None or baseline is None or baseline == 0:
        return "n/a"
    ratio = latest / baseline
    if metric_name == "req_per_sec":
        if ratio < 0.9:
            return "regressed"
        if ratio > 1.1:
            return "improved"
        return "stable"
    if ratio > 1.1:
        return "regressed"
    if ratio < 0.9:
        return "improved"
    return "stable"


def load_history(history_dir: Path):
    snapshots = []
    for path in sorted(history_dir.glob("*.json")):
        try:
            with path.open("r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        if not isinstance(data.get("scenarios"), dict):
            continue
        snapshots.append({"path": str(path), "report": data})
    return snapshots


def build_trend_summary(snapshots, window):
    if not snapshots:
        return {
            "history_count": 0,
            "window_used": 0,
            "scenarios": {},
            "memory": {},
            "summary": {
                "regressed": 0,
                "stable": 0,
                "improved": 0,
                "na": 0,
            },
        }

    latest_entry = snapshots[-1]
    latest = latest_entry["report"]
    previous = snapshots[:-1][-window:] if len(snapshots) > 1 else []

    summary_counts = {
        "regressed": 0,
        "stable": 0,
        "improved": 0,
        "na": 0,
    }
    scenario_summary = {}
    latest_scenarios = latest.get("scenarios", {})
    for scenario_name in sorted(latest_scenarios.keys()):
        latest_metrics = latest_scenarios.get(scenario_name, {})
        metrics = {}
        for metric_name in ("p50_ms", "p95_ms", "p99_ms", "req_per_sec"):
            latest_value = as_float(latest_metrics.get(metric_name), 0.0)
            previous_values = []
            for snapshot in previous:
                scenario_data = snapshot["report"].get("scenarios", {}).get(scenario_name, {})
                if metric_name in scenario_data:
                    previous_values.append(as_float(scenario_data.get(metric_name), 0.0))
            baseline = median(previous_values)
            state = trend_state(metric_name, latest_value, baseline)
            change = percent_change(latest_value, baseline)
            metrics[metric_name] = {
                "latest": latest_value,
                "baseline_median": baseline,
                "change_percent": change,
                "state": state,
            }
            if state == "n/a":
                summary_counts["na"] += 1
            else:
                summary_counts[state] += 1

        scenario_summary[scenario_name] = metrics

    latest_memory = latest.get("memory", {})
    latest_growth = as_int(latest_memory.get("growth_kb"), 0)
    previous_growth = []
    for snapshot in previous:
        growth = snapshot["report"].get("memory", {}).get("growth_kb")
        if growth is not None:
            previous_growth.append(as_int(growth, 0))
    baseline_growth = median(previous_growth)

    return {
        "latest_report_path": latest_entry["path"],
        "latest_timestamp_utc": latest.get("timestamp_utc"),
        "history_count": len(snapshots),
        "window_used": len(previous),
        "scenarios": scenario_summary,
        "memory": {
            "growth_kb_latest": latest_growth,
            "growth_kb_baseline_median": baseline_growth,
            "growth_change_percent": percent_change(latest_growth, baseline_growth),
            "state": trend_state("p95_ms", latest_growth, baseline_growth),
        },
        "summary": summary_counts,
    }


def fmt_change(value):
    if value is None:
        return "n/a"
    return f"{value:+.1f}%"


def write_markdown(path: Path, profile: str, trend):
    lines = []
    lines.append("# Arlen Performance Trend Report")
    lines.append("")
    lines.append(f"- Profile: `{profile}`")
    lines.append(f"- Generated: `{utc_now()}`")
    lines.append(f"- Samples: `{trend.get('history_count', 0)}`")
    lines.append(f"- Comparison window: `{trend.get('window_used', 0)}` previous report(s)")
    lines.append(f"- Latest report: `{trend.get('latest_report_path', '')}`")
    lines.append("")
    lines.append("| Scenario | p50 | p95 | p99 | req/s |")
    lines.append("| --- | --- | --- | --- | --- |")

    scenarios = trend.get("scenarios", {})
    for scenario_name in sorted(scenarios.keys()):
        metrics = scenarios[scenario_name]
        row = [
            scenario_name,
            f"{fmt_change(metrics['p50_ms']['change_percent'])} ({metrics['p50_ms']['state']})",
            f"{fmt_change(metrics['p95_ms']['change_percent'])} ({metrics['p95_ms']['state']})",
            f"{fmt_change(metrics['p99_ms']['change_percent'])} ({metrics['p99_ms']['state']})",
            f"{fmt_change(metrics['req_per_sec']['change_percent'])} ({metrics['req_per_sec']['state']})",
        ]
        lines.append(f"| {row[0]} | {row[1]} | {row[2]} | {row[3]} | {row[4]} |")

    memory = trend.get("memory", {})
    lines.append("")
    lines.append(
        f"- Memory growth: latest `{memory.get('growth_kb_latest', 0)} KB`, "
        f"change `{fmt_change(memory.get('growth_change_percent'))}`"
    )
    summary = trend.get("summary", {})
    lines.append(
        "- Metric states: "
        f"regressed={summary.get('regressed', 0)}, "
        f"stable={summary.get('stable', 0)}, "
        f"improved={summary.get('improved', 0)}, "
        f"n/a={summary.get('na', 0)}"
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        f.write("\n".join(lines))
        f.write("\n")


def main():
    parser = argparse.ArgumentParser(description="Build trend report from archived Arlen perf runs")
    parser.add_argument("--history-dir", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-md", required=True)
    parser.add_argument("--profile", default="default")
    parser.add_argument("--window", type=int, default=10)
    args = parser.parse_args()

    history_dir = Path(args.history_dir)
    history_dir.mkdir(parents=True, exist_ok=True)
    snapshots = load_history(history_dir)
    trend = build_trend_summary(snapshots, max(args.window, 1))

    payload = {
        "schema_version": 1,
        "generated_utc": utc_now(),
        "profile": args.profile,
        "trend": trend,
    }

    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    with output_json.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True)
        f.write("\n")

    write_markdown(Path(args.output_md), args.profile, trend)
    print(f"perf trend: profile={args.profile} history={trend.get('history_count', 0)}")


if __name__ == "__main__":
    main()
