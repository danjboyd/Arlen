#!/usr/bin/env python3
import argparse
import csv
import datetime as dt
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def read_first_line(command) -> str:
    try:
        out = subprocess.check_output(command, stderr=subprocess.STDOUT, text=True)
    except Exception:
        return ""
    lines = [line.strip() for line in out.splitlines() if line.strip()]
    return lines[0] if lines else ""


def read_cpu_model() -> str:
    cpuinfo = Path("/proc/cpuinfo")
    if not cpuinfo.exists():
        return ""
    for line in cpuinfo.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.lower().startswith("model name"):
            parts = line.split(":", 1)
            return parts[1].strip() if len(parts) > 1 else ""
    return ""


def read_mem_total_kb() -> int:
    meminfo = Path("/proc/meminfo")
    if not meminfo.exists():
        return 0
    for line in meminfo.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("MemTotal:"):
            parts = line.split()
            if len(parts) >= 2 and parts[1].isdigit():
                return int(parts[1])
            return 0
    return 0


def run_cmd(command, cwd: Path, env: dict, log_path: Path) -> int:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8") as log_handle:
        process = subprocess.Popen(
            command,
            cwd=str(cwd),
            env=env,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
        return process.wait()


def copy_perf_artifacts(repo_root: Path, destination_dir: Path) -> dict:
    destination_dir.mkdir(parents=True, exist_ok=True)
    copied = {}
    names = [
        "latest.json",
        "latest.csv",
        "latest_runs.csv",
        "latest_trend.json",
        "latest_trend.md",
    ]
    for name in names:
        src = repo_root / "build" / "perf" / name
        if not src.exists():
            continue
        dst = destination_dir / name
        shutil.copyfile(src, dst)
        copied[name] = str(dst)
    return copied


def build_summary_rows(concurrency: int, measured_report: dict):
    rows = []
    scenarios = measured_report.get("scenarios", {})
    for scenario, metrics in sorted(scenarios.items()):
        rows.append(
            {
                "concurrency": concurrency,
                "scenario": scenario,
                "requests": metrics.get("requests", 0),
                "repeats": metrics.get("repeats", 0),
                "p50_ms": metrics.get("p50_ms", 0),
                "p95_ms": metrics.get("p95_ms", 0),
                "p99_ms": metrics.get("p99_ms", 0),
                "max_ms": metrics.get("max_ms", 0),
                "req_per_sec": metrics.get("req_per_sec", 0),
            }
        )
    return rows


def write_summary_csv(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "concurrency",
                "scenario",
                "requests",
                "repeats",
                "p50_ms",
                "p95_ms",
                "p99_ms",
                "max_ms",
                "req_per_sec",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    row["concurrency"],
                    row["scenario"],
                    row["requests"],
                    row["repeats"],
                    f'{float(row["p50_ms"]):.3f}',
                    f'{float(row["p95_ms"]):.3f}',
                    f'{float(row["p99_ms"]):.3f}',
                    f'{float(row["max_ms"]):.3f}',
                    f'{float(row["req_per_sec"]):.2f}',
                ]
            )


def parse_concurrency_list(value: str):
    items = []
    for part in (value or "").split(","):
        token = part.strip()
        if not token:
            continue
        if not token.isdigit():
            raise ValueError(f"invalid concurrency token: {token}")
        parsed = int(token)
        if parsed < 1:
            raise ValueError(f"concurrency must be >= 1: {parsed}")
        items.append(parsed)
    if not items:
        raise ValueError("empty concurrency ladder")
    return items


def main():
    parser = argparse.ArgumentParser(description="Run Phase C benchmark protocol")
    parser.add_argument("--repo-root", default=None, help="Path to Arlen repository root")
    parser.add_argument(
        "--protocol-file",
        default="tests/performance/protocols/phasec_comparison_http.json",
        help="Protocol JSON definition path",
    )
    parser.add_argument(
        "--output-dir",
        default="build/perf/phasec",
        help="Directory for protocol run artifacts",
    )
    parser.add_argument(
        "--run-id",
        default=None,
        help="Optional explicit run id (default UTC timestamp)",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root) if args.repo_root else Path(__file__).resolve().parents[2]
    protocol_path = Path(args.protocol_file)
    if not protocol_path.is_absolute():
        protocol_path = (repo_root / protocol_path).resolve()
    output_root = Path(args.output_dir)
    if not output_root.is_absolute():
        output_root = (repo_root / output_root).resolve()

    protocol = read_json(protocol_path)
    profile = str(os.environ.get("ARLEN_PHASEC_PROFILE", protocol.get("profile", "comparison_http")))
    host = str(os.environ.get("ARLEN_PHASEC_HOST", protocol.get("host", "127.0.0.1")))
    port = int(os.environ.get("ARLEN_PHASEC_PORT", protocol.get("port", 3301)))
    concurrency_ladder = protocol.get("concurrency_ladder", [1, 4, 8, 16, 32])
    if os.environ.get("ARLEN_PHASEC_CONCURRENCY_LIST"):
        concurrency_ladder = parse_concurrency_list(os.environ["ARLEN_PHASEC_CONCURRENCY_LIST"])
    if isinstance(concurrency_ladder, str):
        concurrency_ladder = parse_concurrency_list(concurrency_ladder)
    else:
        concurrency_ladder = [int(v) for v in concurrency_ladder]
        if not concurrency_ladder:
            raise RuntimeError("protocol concurrency_ladder is empty")
        if any(v < 1 for v in concurrency_ladder):
            raise RuntimeError("protocol concurrency_ladder contains values < 1")

    warmup = protocol.get("warmup", {})
    measured = protocol.get("measured", {})
    warmup_requests = int(os.environ.get("ARLEN_PHASEC_WARMUP_REQUESTS", warmup.get("requests", 30)))
    warmup_repeats = int(os.environ.get("ARLEN_PHASEC_WARMUP_REPEATS", warmup.get("repeats", 1)))
    measured_requests = int(os.environ.get("ARLEN_PHASEC_MEASURED_REQUESTS", measured.get("requests", 120)))
    measured_repeats = int(os.environ.get("ARLEN_PHASEC_MEASURED_REPEATS", measured.get("repeats", 3)))

    run_id = args.run_id or dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    run_dir = output_root / "runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    env_base = os.environ.copy()
    env_base["ARLEN_PERF_PROFILE"] = profile
    env_base["ARLEN_PERF_SKIP_GATE"] = "1"
    env_base["ARLEN_PERF_PORT"] = str(port)
    env_base["ARLEN_PERF_SKIP_BUILD"] = "1"

    build_log = run_dir / "logs" / "build_boomhauer.log"
    build_rc = run_cmd(["make", "boomhauer"], repo_root, env_base, build_log)
    if build_rc != 0:
        raise RuntimeError(f"make boomhauer failed (see {build_log})")

    summary_rows = []
    ladder_results = []

    for concurrency in concurrency_ladder:
        ladder_tag = f"c{concurrency}"
        ladder_dir = run_dir / "ladder" / ladder_tag
        logs_dir = ladder_dir / "logs"
        warmup_env = dict(env_base)
        warmup_env["ARLEN_PERF_CONCURRENCY"] = str(concurrency)
        warmup_env["ARLEN_PERF_REQUESTS"] = str(warmup_requests)
        warmup_env["ARLEN_PERF_REPEATS"] = str(warmup_repeats)
        warmup_env["ARLEN_PERF_FAST"] = "1"
        warmup_env["ARLEN_PERF_HISTORY_DIR"] = str(run_dir / "history" / "warmup" / ladder_tag)
        warmup_log = logs_dir / "warmup.log"
        warmup_rc = run_cmd(["bash", "./tests/performance/run_perf.sh"], repo_root, warmup_env, warmup_log)
        if warmup_rc != 0:
            raise RuntimeError(f"warmup failed for concurrency={concurrency} (see {warmup_log})")

        measured_env = dict(env_base)
        measured_env["ARLEN_PERF_CONCURRENCY"] = str(concurrency)
        measured_env["ARLEN_PERF_REQUESTS"] = str(measured_requests)
        measured_env["ARLEN_PERF_REPEATS"] = str(measured_repeats)
        measured_env["ARLEN_PERF_FAST"] = "0"
        measured_env["ARLEN_PERF_HISTORY_DIR"] = str(run_dir / "history" / "measured" / ladder_tag)
        measured_log = logs_dir / "measured.log"
        measured_rc = run_cmd(["bash", "./tests/performance/run_perf.sh"], repo_root, measured_env, measured_log)
        if measured_rc != 0:
            raise RuntimeError(f"measured run failed for concurrency={concurrency} (see {measured_log})")

        artifact_dir = ladder_dir / "artifacts"
        copied = copy_perf_artifacts(repo_root, artifact_dir)
        latest_report = read_json(artifact_dir / "latest.json")
        summary_rows.extend(build_summary_rows(concurrency, latest_report))

        ladder_results.append(
            {
                "concurrency": concurrency,
                "warmup": {
                    "requests": warmup_requests,
                    "repeats": warmup_repeats,
                    "log": str(warmup_log),
                },
                "measured": {
                    "requests": measured_requests,
                    "repeats": measured_repeats,
                    "log": str(measured_log),
                },
                "artifacts": copied,
                "report": latest_report,
            }
        )

    git_sha = read_first_line(["git", "-C", str(repo_root), "rev-parse", "HEAD"])
    git_short = read_first_line(["git", "-C", str(repo_root), "rev-parse", "--short", "HEAD"])
    report = {
        "schema_version": 1,
        "phase": "C",
        "timestamp_utc": utc_now(),
        "run_id": run_id,
        "protocol_file": str(protocol_path),
        "protocol": protocol,
        "execution": {
            "profile": profile,
            "host": host,
            "port": port,
            "concurrency_ladder": concurrency_ladder,
            "warmup_requests": warmup_requests,
            "warmup_repeats": warmup_repeats,
            "measured_requests": measured_requests,
            "measured_repeats": measured_repeats,
            "perf_command": "bash ./tests/performance/run_perf.sh",
        },
        "machine": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "cpu_count": os.cpu_count(),
            "cpu_model": read_cpu_model(),
            "mem_total_kb": read_mem_total_kb(),
        },
        "tool_versions": {
            "clang": read_first_line(["clang", "--version"]),
            "curl": read_first_line(["curl", "--version"]),
            "bash": read_first_line(["bash", "--version"]),
        },
        "git": {
            "sha": git_sha,
            "short_sha": git_short,
        },
        "results": ladder_results,
    }

    summary_csv = run_dir / "phasec_summary.csv"
    write_summary_csv(summary_csv, summary_rows)
    report["summary_csv"] = str(summary_csv)

    report_path = run_dir / "phasec_protocol_report.json"
    write_json(report_path, report)
    latest_path = output_root / "latest_protocol_report.json"
    write_json(latest_path, report)

    print(f"phasec: complete run_id={run_id}")
    print(f"phasec: report={report_path}")
    print(f"phasec: latest={latest_path}")
    print(f"phasec: summary={summary_csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
