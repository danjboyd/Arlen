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
import tarfile
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


def read_first_line(command) -> str:
    try:
        out = subprocess.check_output(command, stderr=subprocess.STDOUT, text=True)
    except Exception:
        return ""
    lines = [line.strip() for line in out.splitlines() if line.strip()]
    return lines[0] if lines else ""


def read_python_module_version(python_bin: str, module: str) -> str:
    cmd = [python_bin, "-c", f"import {module}; print(getattr({module}, '__version__', ''))"]
    return read_first_line(cmd)


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


def as_float(value) -> float:
    try:
        return float(value)
    except Exception:
        return 0.0


def as_int(value) -> int:
    try:
        return int(value)
    except Exception:
        return 0


def pct_delta(current: float, baseline: float) -> float:
    if baseline <= 0:
        return 0.0
    return ((current - baseline) / baseline) * 100.0


def collect_report_rows(pair_name: str, framework_name: str, concurrency: int, report: dict):
    rows = []
    for scenario, metrics in sorted(report.get("scenarios", {}).items()):
        rows.append(
            {
                "pair": pair_name,
                "framework": framework_name,
                "profile": report.get("profile", ""),
                "concurrency": concurrency,
                "scenario": scenario,
                "requests": as_int(metrics.get("requests", 0)),
                "repeats": as_int(metrics.get("repeats", 0)),
                "p50_ms": as_float(metrics.get("p50_ms", 0)),
                "p95_ms": as_float(metrics.get("p95_ms", 0)),
                "p99_ms": as_float(metrics.get("p99_ms", 0)),
                "max_ms": as_float(metrics.get("max_ms", 0)),
                "req_per_sec": as_float(metrics.get("req_per_sec", 0)),
            }
        )
    return rows


def index_reports_by_concurrency(framework_result: dict):
    indexed = {}
    for item in framework_result.get("results", []):
        concurrency = as_int(item.get("concurrency"))
        report = item.get("report", {})
        if concurrency > 0 and isinstance(report, dict):
            indexed[concurrency] = report
    return indexed


def winner_for_latency(arlen_value: float, fastapi_value: float) -> str:
    if arlen_value < fastapi_value:
        return "arlen"
    if fastapi_value < arlen_value:
        return "fastapi"
    return "tie"


def winner_for_throughput(arlen_value: float, fastapi_value: float) -> str:
    if arlen_value > fastapi_value:
        return "arlen"
    if fastapi_value > arlen_value:
        return "fastapi"
    return "tie"


def build_claim_lookup(claim_targets):
    lookup = {}
    for entry in claim_targets:
        if not isinstance(entry, dict):
            continue
        claim_id = str(entry.get("claim_id", "")).strip()
        pair = str(entry.get("pair", "")).strip()
        scenario = str(entry.get("scenario", "")).strip()
        if claim_id and pair and scenario:
            lookup[(pair, scenario)] = claim_id
    return lookup


def build_comparison_rows(pair_results, claim_lookup):
    rows = []
    for pair_result in pair_results:
        pair_name = pair_result.get("name", "")
        frameworks = pair_result.get("frameworks", {})
        arlen = frameworks.get("arlen", {})
        fastapi = frameworks.get("fastapi", {})
        arlen_reports = index_reports_by_concurrency(arlen)
        fastapi_reports = index_reports_by_concurrency(fastapi)
        for concurrency in sorted(set(arlen_reports.keys()) & set(fastapi_reports.keys())):
            arlen_report = arlen_reports[concurrency]
            fastapi_report = fastapi_reports[concurrency]
            arlen_scenarios = arlen_report.get("scenarios", {})
            fastapi_scenarios = fastapi_report.get("scenarios", {})
            for scenario in sorted(set(arlen_scenarios.keys()) & set(fastapi_scenarios.keys())):
                arlen_metrics = arlen_scenarios[scenario]
                fastapi_metrics = fastapi_scenarios[scenario]
                arlen_p50 = as_float(arlen_metrics.get("p50_ms", 0))
                arlen_p95 = as_float(arlen_metrics.get("p95_ms", 0))
                arlen_p99 = as_float(arlen_metrics.get("p99_ms", 0))
                arlen_req = as_float(arlen_metrics.get("req_per_sec", 0))
                fastapi_p50 = as_float(fastapi_metrics.get("p50_ms", 0))
                fastapi_p95 = as_float(fastapi_metrics.get("p95_ms", 0))
                fastapi_p99 = as_float(fastapi_metrics.get("p99_ms", 0))
                fastapi_req = as_float(fastapi_metrics.get("req_per_sec", 0))
                latency_adv_pct = pct_delta(fastapi_p95 - arlen_p95, fastapi_p95)
                throughput_adv_pct = pct_delta(arlen_req, fastapi_req)
                rows.append(
                    {
                        "claim_id": claim_lookup.get((pair_name, scenario), ""),
                        "pair": pair_name,
                        "scenario": scenario,
                        "concurrency": concurrency,
                        "arlen_p50_ms": arlen_p50,
                        "arlen_p95_ms": arlen_p95,
                        "arlen_p99_ms": arlen_p99,
                        "arlen_req_per_sec": arlen_req,
                        "fastapi_p50_ms": fastapi_p50,
                        "fastapi_p95_ms": fastapi_p95,
                        "fastapi_p99_ms": fastapi_p99,
                        "fastapi_req_per_sec": fastapi_req,
                        "latency_advantage_pct": latency_adv_pct,
                        "throughput_advantage_pct": throughput_adv_pct,
                        "latency_winner": winner_for_latency(arlen_p95, fastapi_p95),
                        "throughput_winner": winner_for_throughput(arlen_req, fastapi_req),
                    }
                )
    return rows


def write_framework_summary_csv(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "pair",
                "framework",
                "profile",
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
                    row["pair"],
                    row["framework"],
                    row["profile"],
                    row["concurrency"],
                    row["scenario"],
                    row["requests"],
                    row["repeats"],
                    f'{row["p50_ms"]:.3f}',
                    f'{row["p95_ms"]:.3f}',
                    f'{row["p99_ms"]:.3f}',
                    f'{row["max_ms"]:.3f}',
                    f'{row["req_per_sec"]:.2f}',
                ]
            )


def write_comparison_csv(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "claim_id",
                "pair",
                "scenario",
                "concurrency",
                "arlen_p50_ms",
                "arlen_p95_ms",
                "arlen_p99_ms",
                "arlen_req_per_sec",
                "fastapi_p50_ms",
                "fastapi_p95_ms",
                "fastapi_p99_ms",
                "fastapi_req_per_sec",
                "latency_advantage_pct",
                "throughput_advantage_pct",
                "latency_winner",
                "throughput_winner",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    row["claim_id"],
                    row["pair"],
                    row["scenario"],
                    row["concurrency"],
                    f'{row["arlen_p50_ms"]:.3f}',
                    f'{row["arlen_p95_ms"]:.3f}',
                    f'{row["arlen_p99_ms"]:.3f}',
                    f'{row["arlen_req_per_sec"]:.2f}',
                    f'{row["fastapi_p50_ms"]:.3f}',
                    f'{row["fastapi_p95_ms"]:.3f}',
                    f'{row["fastapi_p99_ms"]:.3f}',
                    f'{row["fastapi_req_per_sec"]:.2f}',
                    f'{row["latency_advantage_pct"]:.2f}',
                    f'{row["throughput_advantage_pct"]:.2f}',
                    row["latency_winner"],
                    row["throughput_winner"],
                ]
            )


def write_comparison_markdown(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Phase D Baseline Comparison Table",
        "",
        "Positive `latency_advantage_pct` means lower Arlen p95 latency than FastAPI.",
        "Positive `throughput_advantage_pct` means higher Arlen throughput than FastAPI.",
        "",
        "| Claim | Pair | Scenario | Concurrency | Arlen p95 ms | FastAPI p95 ms | Latency adv % | Arlen req/s | FastAPI req/s | Throughput adv % |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        claim = row["claim_id"] or "-"
        lines.append(
            "| "
            + " | ".join(
                [
                    claim,
                    row["pair"],
                    row["scenario"],
                    str(row["concurrency"]),
                    f'{row["arlen_p95_ms"]:.3f}',
                    f'{row["fastapi_p95_ms"]:.3f}',
                    f'{row["latency_advantage_pct"]:.2f}',
                    f'{row["arlen_req_per_sec"]:.2f}',
                    f'{row["fastapi_req_per_sec"]:.2f}',
                    f'{row["throughput_advantage_pct"]:.2f}',
                ]
            )
            + " |"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_methodology_markdown(path: Path, payload: dict) -> None:
    execution = payload.get("execution", {})
    machine = payload.get("machine", {})
    tools = payload.get("tool_versions", {})
    git_meta = payload.get("git", {})
    parity = payload.get("parity", {})
    lines = [
        "# Phase D Methodology Note",
        "",
        f"- run_id: `{payload.get('run_id', '')}`",
        f"- timestamp_utc: `{payload.get('timestamp_utc', '')}`",
        f"- parity_gate_passed: `{str(parity.get('passed', False)).lower()}`",
        f"- protocol_file: `{payload.get('protocol_file', '')}`",
        "",
        "## Protocol",
        "",
        f"- host: `{execution.get('host', '127.0.0.1')}`",
        f"- concurrency_ladder: `{','.join([str(v) for v in execution.get('concurrency_ladder', [])])}`",
        f"- warmup: `{execution.get('warmup_requests', 0)} requests x {execution.get('warmup_repeats', 0)} repeats`",
        f"- measured: `{execution.get('measured_requests', 0)} requests x {execution.get('measured_repeats', 0)} repeats`",
        "",
        "## Versions and Machine",
        "",
        f"- git_sha: `{git_meta.get('sha', '')}`",
        f"- platform: `{machine.get('platform', '')}`",
        f"- cpu_model: `{machine.get('cpu_model', '')}`",
        f"- cpu_count: `{machine.get('cpu_count', 0)}`",
        f"- mem_total_kb: `{machine.get('mem_total_kb', 0)}`",
        f"- python: `{machine.get('python', '')}`",
        f"- fastapi: `{tools.get('fastapi', '')}`",
        f"- uvicorn: `{tools.get('uvicorn', '')}`",
        f"- clang: `{tools.get('clang', '')}`",
        f"- curl: `{tools.get('curl', '')}`",
        f"- bash: `{tools.get('bash', '')}`",
        "",
        "## Framework/Profile Matrix",
        "",
    ]
    for pair in execution.get("pairs", []):
        ladder = pair.get("concurrency_ladder", execution.get("concurrency_ladder", []))
        lines.append(
            f"- `{pair.get('name', '')}`: arlen=`{pair.get('arlen_profile', '')}` "
            f"(port `{pair.get('arlen_port', 0)}`), fastapi=`{pair.get('fastapi_profile', '')}` "
            f"(port `{pair.get('fastapi_port', 0)}`), ladder=`{','.join([str(v) for v in ladder])}`"
        )
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def write_artifact_manifest(path: Path, run_dir: Path, skip_names: set) -> dict:
    files = []
    for entry in sorted(run_dir.rglob("*")):
        if not entry.is_file():
            continue
        if entry.name in skip_names:
            continue
        files.append(str(entry.relative_to(run_dir)))
    manifest = {
        "generated_utc": utc_now(),
        "run_dir": str(run_dir),
        "file_count": len(files),
        "files": files,
    }
    write_json(path, manifest)
    return manifest


def build_artifact_bundle(bundle_path: Path, run_dir: Path, relative_files) -> None:
    with tarfile.open(bundle_path, "w:gz") as tar:
        for rel_path in relative_files:
            abs_path = run_dir / rel_path
            if abs_path.exists() and abs_path.is_file():
                tar.add(abs_path, arcname=rel_path)


def parse_pairs(protocol_pairs):
    if not isinstance(protocol_pairs, list) or not protocol_pairs:
        raise RuntimeError("protocol pairs must be a non-empty list")
    parsed = []
    required_fields = [
        "name",
        "arlen_profile",
        "fastapi_profile",
        "arlen_port",
        "fastapi_port",
    ]
    for entry in protocol_pairs:
        if not isinstance(entry, dict):
            raise RuntimeError("pair entry must be an object")
        missing = [field for field in required_fields if field not in entry]
        if missing:
            raise RuntimeError(f"pair entry missing fields: {', '.join(missing)}")
        parsed.append(
            {
                "name": str(entry["name"]),
                "arlen_profile": str(entry["arlen_profile"]),
                "fastapi_profile": str(entry["fastapi_profile"]),
                "arlen_port": as_int(entry["arlen_port"]),
                "fastapi_port": as_int(entry["fastapi_port"]),
            }
        )
        if "concurrency_ladder" in entry:
            ladder = entry.get("concurrency_ladder", [])
            if isinstance(ladder, str):
                ladder = parse_concurrency_list(ladder)
            elif isinstance(ladder, list):
                ladder = [as_int(value) for value in ladder]
                if not ladder or any(value < 1 for value in ladder):
                    raise RuntimeError(f"pair {entry.get('name', '<unknown>')} has invalid concurrency_ladder")
            else:
                raise RuntimeError(f"pair {entry.get('name', '<unknown>')} has invalid concurrency_ladder type")
            parsed[-1]["concurrency_ladder"] = ladder
    return parsed


def ensure_fastapi_venv(repo_root: Path, run_dir: Path, env: dict) -> str:
    venv_default = repo_root / "build" / "venv" / "fastapi_parity"
    venv_dir = Path(os.environ.get("ARLEN_FASTAPI_VENV", str(venv_default)))
    if not venv_dir.is_absolute():
        venv_dir = (repo_root / venv_dir).resolve()
    requirements = (repo_root / "tests" / "performance" / "fastapi_reference" / "requirements.txt").resolve()
    bootstrap_python = os.environ.get("ARLEN_PHASED_BOOTSTRAP_PYTHON", "python3")

    venv_log = run_dir / "logs" / "fastapi_venv.log"
    rc = run_cmd([bootstrap_python, "-m", "venv", str(venv_dir)], repo_root, env, venv_log)
    if rc != 0:
        raise RuntimeError(f"fastapi venv creation failed (see {venv_log})")

    venv_python = venv_dir / "bin" / "python3"
    if not venv_python.exists():
        venv_python = venv_dir / "bin" / "python"
    if not venv_python.exists():
        raise RuntimeError(f"fastapi venv python not found: {venv_dir}")

    pip_upgrade_log = run_dir / "logs" / "fastapi_pip_upgrade.log"
    rc = run_cmd([str(venv_python), "-m", "pip", "install", "--upgrade", "pip"], repo_root, env, pip_upgrade_log)
    if rc != 0:
        raise RuntimeError(f"pip upgrade failed (see {pip_upgrade_log})")

    pip_install_log = run_dir / "logs" / "fastapi_requirements.log"
    rc = run_cmd(
        [str(venv_python), "-m", "pip", "install", "-r", str(requirements)],
        repo_root,
        env,
        pip_install_log,
    )
    if rc != 0:
        raise RuntimeError(f"fastapi requirements install failed (see {pip_install_log})")
    return str(venv_python)


def run_phaseb_parity(repo_root: Path, run_dir: Path, python_bin: str, env: dict) -> dict:
    parity_dir = run_dir / "parity"
    parity_report = parity_dir / "parity_fastapi_report.json"
    parity_log = parity_dir / "parity_check.log"
    command = [
        python_bin,
        "tests/performance/check_parity_fastapi.py",
        "--repo-root",
        str(repo_root),
        "--arlen-bin",
        "./build/boomhauer",
        "--fastapi-app-dir",
        "tests/performance/fastapi_reference",
        "--python-bin",
        python_bin,
        "--output",
        str(parity_report),
    ]
    rc = run_cmd(command, repo_root, env, parity_log)
    if rc != 0:
        raise RuntimeError(f"phaseb parity check failed (see {parity_log})")
    report = read_json(parity_report)
    if not bool(report.get("passed", False)):
        raise RuntimeError("phaseb parity report did not pass")
    latest_parity = repo_root / "build" / "perf" / "parity_fastapi_latest.json"
    latest_parity.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(parity_report, latest_parity)
    return {
        "passed": True,
        "report": report,
        "report_path": str(parity_report),
        "log_path": str(parity_log),
        "latest_report_path": str(latest_parity),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Phase D baseline benchmark campaign")
    parser.add_argument("--repo-root", default=None, help="Path to Arlen repository root")
    parser.add_argument(
        "--protocol-file",
        default="tests/performance/protocols/phased_baseline_campaign.json",
        help="Phase D protocol JSON path",
    )
    parser.add_argument(
        "--output-dir",
        default="build/perf/phased",
        help="Phase D output directory",
    )
    parser.add_argument("--run-id", default=None, help="Optional explicit run id")
    args = parser.parse_args()

    repo_root = Path(args.repo_root) if args.repo_root else Path(__file__).resolve().parents[2]
    protocol_path = Path(args.protocol_file)
    if not protocol_path.is_absolute():
        protocol_path = (repo_root / protocol_path).resolve()
    output_root = Path(args.output_dir)
    if not output_root.is_absolute():
        output_root = (repo_root / output_root).resolve()

    protocol = read_json(protocol_path)
    host = str(os.environ.get("ARLEN_PHASED_HOST", protocol.get("host", "127.0.0.1")))
    concurrency_ladder = protocol.get("concurrency_ladder", [1, 4, 8, 16, 32])
    if os.environ.get("ARLEN_PHASED_CONCURRENCY_LIST"):
        concurrency_ladder = parse_concurrency_list(os.environ["ARLEN_PHASED_CONCURRENCY_LIST"])
    elif isinstance(concurrency_ladder, str):
        concurrency_ladder = parse_concurrency_list(concurrency_ladder)
    else:
        concurrency_ladder = [as_int(value) for value in concurrency_ladder]
        if not concurrency_ladder or any(value < 1 for value in concurrency_ladder):
            raise RuntimeError("invalid concurrency ladder in protocol")

    warmup = protocol.get("warmup", {})
    measured = protocol.get("measured", {})
    warmup_requests = as_int(os.environ.get("ARLEN_PHASED_WARMUP_REQUESTS", warmup.get("requests", 30)))
    warmup_repeats = as_int(os.environ.get("ARLEN_PHASED_WARMUP_REPEATS", warmup.get("repeats", 1)))
    measured_requests = as_int(os.environ.get("ARLEN_PHASED_MEASURED_REQUESTS", measured.get("requests", 120)))
    measured_repeats = as_int(os.environ.get("ARLEN_PHASED_MEASURED_REPEATS", measured.get("repeats", 3)))
    pairs = parse_pairs(protocol.get("pairs", []))

    run_id = args.run_id or dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    run_dir = output_root / "runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    env_base = os.environ.copy()
    env_base["ARLEN_PERF_SKIP_GATE"] = "1"
    env_base["ARLEN_PERF_SKIP_BUILD"] = "1"

    if os.environ.get("ARLEN_PHASED_SKIP_BUILD", "0") != "1":
        build_log = run_dir / "logs" / "build_boomhauer.log"
        build_rc = run_cmd(["make", "boomhauer"], repo_root, env_base, build_log)
        if build_rc != 0:
            raise RuntimeError(f"make boomhauer failed (see {build_log})")

    fastapi_python = ensure_fastapi_venv(repo_root, run_dir, env_base)

    if os.environ.get("ARLEN_PHASED_SKIP_PARITY", "0") == "1":
        parity_result = {
            "passed": False,
            "skipped": True,
            "reason": "ARLEN_PHASED_SKIP_PARITY=1",
        }
    else:
        parity_result = run_phaseb_parity(repo_root, run_dir, fastapi_python, env_base)

    framework_rows = []
    pair_results = []
    for pair in pairs:
        pair_name = pair["name"]
        pair_ladder = pair.get("concurrency_ladder", concurrency_ladder)
        framework_results = {}
        for framework_name, profile_key, port_key in [
            ("arlen", "arlen_profile", "arlen_port"),
            ("fastapi", "fastapi_profile", "fastapi_port"),
        ]:
            profile = pair[profile_key]
            port = as_int(pair[port_key])
            ladder_results = []
            for concurrency in pair_ladder:
                ladder_tag = f"c{concurrency}"
                ladder_dir = run_dir / "pairs" / pair_name / framework_name / "ladder" / ladder_tag
                logs_dir = ladder_dir / "logs"

                warmup_env = dict(env_base)
                warmup_env["ARLEN_PERF_PROFILE"] = profile
                warmup_env["ARLEN_PERF_PORT"] = str(port)
                warmup_env["ARLEN_PERF_CONCURRENCY"] = str(concurrency)
                warmup_env["ARLEN_PERF_REQUESTS"] = str(warmup_requests)
                warmup_env["ARLEN_PERF_REPEATS"] = str(warmup_repeats)
                warmup_env["ARLEN_PERF_FAST"] = "1"
                warmup_env["ARLEN_PERF_HISTORY_DIR"] = str(
                    run_dir / "history" / pair_name / framework_name / "warmup" / ladder_tag
                )
                if framework_name == "fastapi":
                    warmup_env["ARLEN_FASTAPI_PYTHON"] = fastapi_python
                warmup_log = logs_dir / "warmup.log"
                warmup_rc = run_cmd(["bash", "./tests/performance/run_perf.sh"], repo_root, warmup_env, warmup_log)
                if warmup_rc != 0:
                    raise RuntimeError(
                        f"warmup failed pair={pair_name} framework={framework_name} concurrency={concurrency} (see {warmup_log})"
                    )

                measured_env = dict(env_base)
                measured_env["ARLEN_PERF_PROFILE"] = profile
                measured_env["ARLEN_PERF_PORT"] = str(port)
                measured_env["ARLEN_PERF_CONCURRENCY"] = str(concurrency)
                measured_env["ARLEN_PERF_REQUESTS"] = str(measured_requests)
                measured_env["ARLEN_PERF_REPEATS"] = str(measured_repeats)
                measured_env["ARLEN_PERF_FAST"] = "0"
                measured_env["ARLEN_PERF_HISTORY_DIR"] = str(
                    run_dir / "history" / pair_name / framework_name / "measured" / ladder_tag
                )
                if framework_name == "fastapi":
                    measured_env["ARLEN_FASTAPI_PYTHON"] = fastapi_python
                measured_log = logs_dir / "measured.log"
                measured_rc = run_cmd(["bash", "./tests/performance/run_perf.sh"], repo_root, measured_env, measured_log)
                if measured_rc != 0:
                    raise RuntimeError(
                        f"measured run failed pair={pair_name} framework={framework_name} concurrency={concurrency} (see {measured_log})"
                    )

                artifacts_dir = ladder_dir / "artifacts"
                copied = copy_perf_artifacts(repo_root, artifacts_dir)
                latest_report_path = artifacts_dir / "latest.json"
                if not latest_report_path.exists():
                    raise RuntimeError(
                        f"expected measured report missing for pair={pair_name} framework={framework_name} concurrency={concurrency}"
                    )
                measured_report = read_json(latest_report_path)
                framework_rows.extend(
                    collect_report_rows(
                        pair_name=pair_name,
                        framework_name=framework_name,
                        concurrency=concurrency,
                        report=measured_report,
                    )
                )
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
                        "report": measured_report,
                    }
                )

            framework_results[framework_name] = {
                "profile": profile,
                "port": port,
                "results": ladder_results,
            }

        pair_results.append(
            {
                "name": pair_name,
                "concurrency_ladder": pair_ladder,
                "frameworks": framework_results,
            }
        )

    claim_lookup = build_claim_lookup(protocol.get("claim_targets", []))
    comparison_rows = build_comparison_rows(pair_results, claim_lookup)

    framework_summary_csv = run_dir / "phased_framework_summary.csv"
    comparison_csv = run_dir / "phased_comparison.csv"
    comparison_md = run_dir / "phased_comparison.md"
    write_framework_summary_csv(framework_summary_csv, framework_rows)
    write_comparison_csv(comparison_csv, comparison_rows)
    write_comparison_markdown(comparison_md, comparison_rows)

    git_sha = read_first_line(["git", "-C", str(repo_root), "rev-parse", "HEAD"])
    git_short = read_first_line(["git", "-C", str(repo_root), "rev-parse", "--short", "HEAD"])
    report = {
        "schema_version": 1,
        "phase": "D",
        "timestamp_utc": utc_now(),
        "run_id": run_id,
        "protocol_file": str(protocol_path),
        "protocol": protocol,
        "execution": {
            "host": host,
            "concurrency_ladder": concurrency_ladder,
            "warmup_requests": warmup_requests,
            "warmup_repeats": warmup_repeats,
            "measured_requests": measured_requests,
            "measured_repeats": measured_repeats,
            "pairs": pairs,
            "perf_command": "bash ./tests/performance/run_perf.sh",
            "parity_command": "python3 tests/performance/check_parity_fastapi.py",
        },
        "machine": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "cpu_count": os.cpu_count(),
            "cpu_model": read_cpu_model(),
            "mem_total_kb": read_mem_total_kb(),
        },
        "tool_versions": {
            "fastapi": read_python_module_version(fastapi_python, "fastapi"),
            "uvicorn": read_python_module_version(fastapi_python, "uvicorn"),
            "clang": read_first_line(["clang", "--version"]),
            "curl": read_first_line(["curl", "--version"]),
            "bash": read_first_line(["bash", "--version"]),
        },
        "git": {
            "sha": git_sha,
            "short_sha": git_short,
        },
        "parity": parity_result,
        "results": pair_results,
        "comparison": {
            "framework_summary_csv": str(framework_summary_csv),
            "comparison_csv": str(comparison_csv),
            "comparison_md": str(comparison_md),
            "rows": comparison_rows,
        },
    }

    methodology_md = run_dir / "phased_methodology.md"
    write_methodology_markdown(methodology_md, report)
    report["comparison"]["methodology_md"] = str(methodology_md)

    report_path = run_dir / "phased_campaign_report.json"
    latest_report_path = output_root / "latest_campaign_report.json"
    write_json(report_path, report)
    write_json(latest_report_path, report)

    latest_comparison_csv = output_root / "latest_comparison.csv"
    latest_comparison_md = output_root / "latest_comparison.md"
    latest_methodology = output_root / "latest_methodology.md"
    shutil.copyfile(comparison_csv, latest_comparison_csv)
    shutil.copyfile(comparison_md, latest_comparison_md)
    shutil.copyfile(methodology_md, latest_methodology)

    manifest_path = run_dir / "artifact_manifest.json"
    bundle_name = "phased_raw_artifacts.tar.gz"
    manifest = write_artifact_manifest(manifest_path, run_dir, {bundle_name})
    bundle_path = run_dir / bundle_name
    build_artifact_bundle(bundle_path, run_dir, manifest.get("files", []))

    report["comparison"]["artifact_manifest"] = str(manifest_path)
    report["comparison"]["artifact_bundle"] = str(bundle_path)
    write_json(report_path, report)
    write_json(latest_report_path, report)

    print(f"phased: complete run_id={run_id}")
    print(f"phased: report={report_path}")
    print(f"phased: latest={latest_report_path}")
    print(f"phased: comparison_csv={comparison_csv}")
    print(f"phased: methodology={methodology_md}")
    print(f"phased: bundle={bundle_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
