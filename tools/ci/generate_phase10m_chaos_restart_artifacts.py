#!/usr/bin/env python3
"""Generate Phase 10M chaos/restart reliability artifacts."""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

VERSION = "phase10m-chaos-restart-v1"
THRESHOLD_VERSION = "phase10m-chaos-restart-thresholds-v1"


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
        return (
            subprocess.check_output(
                ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
                stderr=subprocess.DEVNULL,
                text=True,
            )
            .strip()
        )
    except Exception:
        return "unknown"


def allocate_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def wait_ready(port: int, timeout_seconds: float = 15.0) -> None:
    deadline = time.time() + timeout_seconds
    last_error = ""
    while time.time() < deadline:
        try:
            body = (
                urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=1.5)
                .read()
                .decode("utf-8")
            )
            if body == "ok\n":
                return
            last_error = f"unexpected health body: {body!r}"
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(0.2)
    raise RuntimeError(f"server failed readiness probe: {last_error}")


def child_pids(parent_pid: int) -> List[int]:
    result = subprocess.run(
        ["ps", "-o", "pid=", "--ppid", str(parent_pid)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    pids: List[int] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            pids.append(int(line))
        except Exception:
            continue
    return pids


def render_markdown(payload: Dict[str, Any], output_dir: Path) -> str:
    lines: List[str] = []
    lines.append("# Phase 10M Chaos Restart")
    lines.append("")
    lines.append(f"Generated at: `{payload['generated_at']}`")
    lines.append(f"Git commit: `{payload['commit']}`")
    lines.append(f"Threshold fixture: `{payload.get('threshold_fixture_version', '')}`")
    lines.append("")
    summary = payload.get("summary", {})
    lines.append("## Summary")
    lines.append("")
    lines.append(f"- Status: `{summary.get('status', 'fail')}`")
    lines.append(f"- Requests observed: `{summary.get('request_total', 0)}`")
    lines.append(f"- Non-200 responses: `{summary.get('non_200', 0)}`")
    lines.append(f"- Load errors: `{summary.get('load_errors', 0)}`")
    lines.append(f"- Transient load faults: `{summary.get('transient_load_faults', 0)}`")
    lines.append(f"- Churn cycles: `{summary.get('churn_cycles', 0)}`")
    lines.append(f"- Manager exit code: `{summary.get('manager_exit_code', -1)}`")
    lines.append("")
    lines.append("## Cycle Events")
    lines.append("")
    lines.append("| Cycle | Killed Worker PID | Health After |")
    lines.append("| --- | --- | --- |")
    for cycle in payload.get("cycle_events", []):
        lines.append(
            "| {cycle} | {killed} | {healthy} |".format(
                cycle=cycle.get("cycle", 0),
                killed=cycle.get("killed_worker_pid", 0),
                healthy="yes" if cycle.get("healthy_after_cycle") else "no",
            )
        )

    lines.append("")
    lines.append("## Violations")
    lines.append("")
    violations = payload.get("violations", [])
    if isinstance(violations, list) and violations:
        for item in violations:
            lines.append(f"- {item}")
    else:
        lines.append("- none")

    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def is_transient_load_fault(exc: BaseException) -> bool:
    message = str(exc).lower()
    return (
        "timed out" in message
        or "connection reset" in message
        or "connection refused" in message
        or "closed before headers" in message
        or "remote end closed" in message
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 10M chaos/restart artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--output-dir", default="build/release_confidence/phase10m/chaos_restart")
    parser.add_argument(
        "--thresholds",
        default="tests/fixtures/runtime/phase10m_chaos_restart_thresholds.json",
    )
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    thresholds_path = (repo_root / args.thresholds).resolve()
    app_root = (repo_root / "examples/tech_demo").resolve()
    propane = (repo_root / "bin/propane").resolve()

    thresholds = load_json(thresholds_path)
    if thresholds.get("version") != THRESHOLD_VERSION:
        raise SystemExit("phase10m chaos threshold fixture version mismatch")

    workers = int(thresholds.get("workers", 2))
    churn_cycles = int(thresholds.get("churnCycles", 2))
    load_threads = int(thresholds.get("loadThreads", 6))
    load_duration = float(thresholds.get("loadDurationSeconds", 5))
    startup_timeout = float(thresholds.get("startupTimeoutSeconds", 60))
    cycle_ready_timeout = float(thresholds.get("cycleReadinessTimeoutSeconds", 25))
    max_non_200 = int(thresholds.get("maxNon200Responses", 8))
    max_load_errors = int(thresholds.get("maxLoadErrors", 8))
    allowed_exit_codes = thresholds.get("allowedManagerExitCodes", [0, -15])
    if not isinstance(allowed_exit_codes, list) or not allowed_exit_codes:
        allowed_exit_codes = [0, -15]
    allowed_exit_codes = [int(value) for value in allowed_exit_codes]
    required_tokens = thresholds.get("requiredLifecycleTokens", [])
    if not isinstance(required_tokens, list):
        required_tokens = []

    port = allocate_free_port()
    pid_file = output_dir / "phase10m_chaos_manager.pid"
    lifecycle_log = output_dir / "phase10m_chaos_lifecycle.log"
    output_dir.mkdir(parents=True, exist_ok=True)
    if pid_file.exists():
        pid_file.unlink()
    if lifecycle_log.exists():
        lifecycle_log.unlink()

    env = dict(os.environ)
    env["ARLEN_FRAMEWORK_ROOT"] = str(repo_root)
    env["ARLEN_APP_ROOT"] = str(app_root)
    env["ARLEN_PROPANE_LIFECYCLE_LOG"] = str(lifecycle_log)

    command = [
        str(propane),
        "--workers",
        str(workers),
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--env",
        "development",
        "--pid-file",
        str(pid_file),
    ]

    manager = subprocess.Popen(
        command,
        cwd=str(repo_root),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    request_total = 0
    non_200 = 0
    load_errors: List[str] = []
    transient_load_faults = 0
    cycle_events: List[Dict[str, Any]] = []
    stop_event = threading.Event()
    lock = threading.Lock()

    def load_worker() -> None:
        nonlocal request_total, non_200, transient_load_faults
        while not stop_event.is_set():
            for path in ("/healthz", "/api/sleep?ms=40"):
                if stop_event.is_set():
                    break
                try:
                    with urllib.request.urlopen(
                        f"http://127.0.0.1:{port}{path}", timeout=2.5
                    ) as response:
                        body = response.read().decode("utf-8", "replace")
                        status = int(response.status)
                    with lock:
                        request_total += 1
                        if status != 200:
                            non_200 += 1
                    if path == "/healthz" and body != "ok\n":
                        with lock:
                            load_errors.append(f"health body mismatch: {body!r}")
                except urllib.error.HTTPError as exc:
                    _ = exc.read()
                    with lock:
                        request_total += 1
                        non_200 += 1
                except Exception as exc:  # noqa: BLE001
                    with lock:
                        if is_transient_load_fault(exc):
                            transient_load_faults += 1
                        else:
                            load_errors.append(str(exc))
                time.sleep(0.015)

    workers_threads = [threading.Thread(target=load_worker) for _ in range(max(load_threads, 1))]

    violations: List[str] = []
    missing_tokens: List[str] = []
    manager_exit_code = -1

    try:
        wait_ready(port, timeout_seconds=startup_timeout)
        for thread in workers_threads:
            thread.start()

        cycle_start = time.time()
        for cycle in range(1, churn_cycles + 1):
            children = child_pids(manager.pid)
            if not children:
                violations.append(f"cycle {cycle}: no worker children detected")
                break
            killed_pid = children[0]
            os.kill(killed_pid, signal.SIGKILL)
            os.kill(manager.pid, signal.SIGHUP)
            healthy = True
            try:
                wait_ready(port, timeout_seconds=cycle_ready_timeout)
            except Exception as exc:  # noqa: BLE001
                healthy = False
                violations.append(f"cycle {cycle}: health check failed after churn ({exc})")
            cycle_events.append(
                {
                    "cycle": cycle,
                    "killed_worker_pid": killed_pid,
                    "healthy_after_cycle": healthy,
                }
            )
            time.sleep(0.2)

        while time.time() - cycle_start < load_duration:
            time.sleep(0.05)

        stop_event.set()
        for thread in workers_threads:
            thread.join(timeout=6)

        os.kill(manager.pid, signal.SIGTERM)
        manager_exit_code = manager.wait(timeout=15)

        lifecycle_text = lifecycle_log.read_text(encoding="utf-8", errors="replace") if lifecycle_log.exists() else ""
        for token in required_tokens:
            token_value = str(token)
            if token_value and token_value not in lifecycle_text:
                missing_tokens.append(token_value)
        if missing_tokens:
            violations.append("missing lifecycle diagnostics: " + ", ".join(missing_tokens))

    except Exception as exc:  # noqa: BLE001
        violations.append(str(exc))
    finally:
        stop_event.set()
        for thread in workers_threads:
            if thread.is_alive():
                thread.join(timeout=1)
        if manager.poll() is None:
            manager.terminate()
            try:
                manager.wait(timeout=8)
            except subprocess.TimeoutExpired:
                manager.kill()
                manager.wait(timeout=5)
        if manager_exit_code == -1:
            manager_exit_code = int(manager.returncode if manager.returncode is not None else -1)

    if non_200 > max_non_200:
        violations.append(f"non-200 responses {non_200} exceed maxNon200Responses {max_non_200}")
    if len(load_errors) > max_load_errors:
        violations.append(f"load errors {len(load_errors)} exceed maxLoadErrors {max_load_errors}")
    if manager_exit_code not in allowed_exit_codes:
        violations.append(
            "manager exit code "
            f"{manager_exit_code} not in allowedManagerExitCodes {allowed_exit_codes}"
        )

    status = "pass" if not violations else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": git_commit(repo_root),
        "threshold_fixture": str(thresholds_path),
        "threshold_fixture_version": thresholds.get("version", ""),
        "thresholds": thresholds,
        "port": port,
        "manager_pid": manager.pid,
        "cycle_events": cycle_events,
        "load_errors": load_errors,
        "violations": violations,
        "summary": {
            "request_total": request_total,
            "non_200": non_200,
            "load_errors": len(load_errors),
            "transient_load_faults": transient_load_faults,
            "missing_lifecycle_tokens": missing_tokens,
            "churn_cycles": churn_cycles,
            "manager_exit_code": manager_exit_code,
            "status": status,
        },
    }

    write_json(output_dir / "chaos_restart_results.json", payload)
    (output_dir / "phase10m_chaos_restart.md").write_text(
        render_markdown(payload, output_dir),
        encoding="utf-8",
    )
    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": payload["commit"],
        "status": status,
        "artifacts": [
            "chaos_restart_results.json",
            "phase10m_chaos_restart.md",
            "phase10m_chaos_lifecycle.log",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase10m-chaos-restart: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
