#!/usr/bin/env python3
"""Generate Phase 10M long-run soak reliability artifacts."""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple

VERSION = "phase10m-soak-v1"
THRESHOLD_VERSION = "phase10m-soak-thresholds-v1"


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


def read_http_response(sock: socket.socket) -> Tuple[str, Dict[str, str], bytes]:
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("closed before headers")
        data += chunk
    head, rest = data.split(b"\r\n\r\n", 1)
    lines = head.decode("utf-8", "replace").split("\r\n")
    status = lines[0]
    headers: Dict[str, str] = {}
    for line in lines[1:]:
        if ":" not in line:
            continue
        name, value = line.split(":", 1)
        headers[name.strip().lower()] = value.strip()

    length = int(headers.get("content-length", "0"))
    body = rest
    while len(body) < length:
        chunk = sock.recv(4096)
        if not chunk:
            break
        body += chunk
    return status, headers, body[:length]


def wait_ready(port: int, timeout_seconds: float = 12.0) -> None:
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
        time.sleep(0.15)
    raise RuntimeError(f"server failed readiness probe: {last_error}")


def start_server(binary: Path, mode: str, port: int) -> subprocess.Popen[str]:
    command = [str(binary), "--port", str(port)]
    if mode == "serialized":
        command = [str(binary), "--env", "production", "--port", str(port)]
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_ready(port)
    except Exception:
        stop_server(process)
        raise
    return process


def stop_server(process: subprocess.Popen[str] | None) -> None:
    if process is None:
        return
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def read_process_metrics(pid: int) -> Dict[str, int]:
    status_path = Path(f"/proc/{pid}/status")
    fd_path = Path(f"/proc/{pid}/fd")
    rss_kb = -1
    for line in status_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("VmRSS:"):
            parts = line.split()
            if len(parts) >= 2 and parts[1].isdigit():
                rss_kb = int(parts[1])
            break
    fd_count = 0
    socket_fd_count = 0
    for entry in fd_path.iterdir():
        fd_count += 1
        try:
            target = os.readlink(entry)
        except OSError:
            continue
        if target.startswith("socket:"):
            socket_fd_count += 1
    return {
        "rss_kb": rss_kb,
        "fd_count": fd_count,
        "socket_fd_count": socket_fd_count,
    }


def request_single_health(port: int) -> Tuple[int, str]:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=3.0) as response:
        body = response.read().decode("utf-8")
        return response.status, body


def run_keepalive_batch(port: int, request_count: int, pipelined: bool) -> Tuple[int, int]:
    if request_count <= 0:
        return 0, 0
    failures = 0
    sent = 0
    sock = socket.create_connection(("127.0.0.1", port), timeout=4)
    sock.settimeout(4)
    try:
        if pipelined and request_count >= 2:
            first = (
                f"GET /healthz HTTP/1.1\r\n"
                f"Host: 127.0.0.1:{port}\r\n"
                "Connection: keep-alive\r\n\r\n"
            ).encode("utf-8")
            second = (
                f"GET /healthz HTTP/1.1\r\n"
                f"Host: 127.0.0.1:{port}\r\n"
                "Connection: keep-alive\r\n\r\n"
            ).encode("utf-8")
            sock.sendall(first + second)
            for _ in range(2):
                status, _, body = read_http_response(sock)
                sent += 1
                if "200" not in status or body != b"ok\n":
                    failures += 1
            request_count -= 2

        for idx in range(request_count):
            connection = "close" if idx == request_count - 1 else "keep-alive"
            request = (
                f"GET /healthz HTTP/1.1\r\n"
                f"Host: 127.0.0.1:{port}\r\n"
                f"Connection: {connection}\r\n\r\n"
            ).encode("utf-8")
            sock.sendall(request)
            status, _, body = read_http_response(sock)
            sent += 1
            if "200" not in status or body != b"ok\n":
                failures += 1
    except Exception:
        remaining = request_count - max(sent, 0)
        failures += max(remaining, 0)
        return request_count, failures
    finally:
        try:
            sock.close()
        except OSError:
            pass
    return sent, failures


def max_metric(samples: List[Dict[str, Any]], key: str) -> int:
    values = [int(sample.get(key, -1)) for sample in samples if isinstance(sample.get(key), int)]
    if not values:
        return -1
    return max(values)


def run_mode(binary: Path, mode: str, thresholds: Dict[str, Any]) -> Dict[str, Any]:
    requests = int(thresholds.get("requestsPerMode", 400))
    sample_every = max(1, int(thresholds.get("sampleEveryRequests", 80)))
    restart_cycles = max(0, int(thresholds.get("restartCycles", 1)))
    max_request_failures = int(thresholds.get("maxRequestFailures", 0))
    max_rss_delta = int(thresholds.get("maxRssDeltaKB", 131072))
    max_fd_delta = int(thresholds.get("maxFDDelta", 96))
    max_socket_fd_delta = int(thresholds.get("maxSocketFDDelta", 96))

    process: subprocess.Popen[str] | None = None
    port = allocate_free_port()
    failures = 0
    completed = 0
    restart_errors: List[str] = []
    samples: List[Dict[str, Any]] = []

    try:
        process = start_server(binary, mode, port)
        baseline = read_process_metrics(process.pid)
        samples.append({"request_index": 0, **baseline})

        while completed < requests:
            if mode == "serialized":
                try:
                    status, body = request_single_health(port)
                    if status != 200 or body != "ok\n":
                        failures += 1
                except Exception:
                    failures += 1
                completed += 1
            else:
                batch = min(8, requests - completed)
                sent, batch_failures = run_keepalive_batch(
                    port=port,
                    request_count=batch,
                    pipelined=(completed % 32 == 0),
                )
                if sent <= 0:
                    sent = batch
                completed += sent
                failures += batch_failures

            if completed % sample_every == 0 or completed >= requests:
                samples.append({"request_index": completed, **read_process_metrics(process.pid)})

        max_rss = max_metric(samples, "rss_kb")
        max_fd = max_metric(samples, "fd_count")
        max_socket_fd = max_metric(samples, "socket_fd_count")
        rss_delta = max_rss - baseline["rss_kb"]
        fd_delta = max_fd - baseline["fd_count"]
        socket_fd_delta = max_socket_fd - baseline["socket_fd_count"]

        restarts = []
        for cycle in range(1, restart_cycles + 1):
            stop_server(process)
            process = None
            port = allocate_free_port()
            process = start_server(binary, mode, port)
            try:
                status, body = request_single_health(port)
                restart_ok = (status == 200 and body == "ok\n")
            except Exception as exc:  # noqa: BLE001
                restart_ok = False
                restart_errors.append(str(exc))
            restarts.append({"cycle": cycle, "ok": restart_ok})
            if not restart_ok:
                restart_errors.append(f"mode {mode} restart cycle {cycle} failed")

        violations: List[str] = []
        if failures > max_request_failures:
            violations.append(
                f"request failures {failures} exceed maxRequestFailures {max_request_failures}"
            )
        if rss_delta > max_rss_delta:
            violations.append(f"rss delta {rss_delta} > maxRssDeltaKB {max_rss_delta}")
        if fd_delta > max_fd_delta:
            violations.append(f"fd delta {fd_delta} > maxFDDelta {max_fd_delta}")
        if socket_fd_delta > max_socket_fd_delta:
            violations.append(
                f"socket fd delta {socket_fd_delta} > maxSocketFDDelta {max_socket_fd_delta}"
            )
        violations.extend(restart_errors)

        return {
            "mode": mode,
            "status": "pass" if not violations else "fail",
            "requests_target": requests,
            "requests_completed": completed,
            "request_failures": failures,
            "baseline": baseline,
            "max_observed": {
                "rss_kb": max_rss,
                "fd_count": max_fd,
                "socket_fd_count": max_socket_fd,
            },
            "deltas": {
                "rss_kb": rss_delta,
                "fd_count": fd_delta,
                "socket_fd_count": socket_fd_delta,
            },
            "restart_cycles": restart_cycles,
            "restart_results": restarts,
            "samples": samples,
            "violations": violations,
        }
    finally:
        stop_server(process)


def render_markdown(payload: Dict[str, Any], output_dir: Path) -> str:
    lines: List[str] = []
    lines.append("# Phase 10M Long-Run Soak")
    lines.append("")
    lines.append(f"Generated at: `{payload['generated_at']}`")
    lines.append(f"Git commit: `{payload['commit']}`")
    lines.append(f"Threshold fixture: `{payload.get('threshold_fixture_version', '')}`")
    lines.append("")
    lines.append("| Mode | Status | Requests | Failures | RSS delta (KB) | FD delta | Socket FD delta |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for result in payload.get("results", []):
        lines.append(
            "| {mode} | {status} | {completed}/{target} | {failures} | {rss} | {fd} | {socket_fd} |".format(
                mode=result.get("mode", ""),
                status=result.get("status", ""),
                completed=result.get("requests_completed", 0),
                target=result.get("requests_target", 0),
                failures=result.get("request_failures", 0),
                rss=result.get("deltas", {}).get("rss_kb", 0),
                fd=result.get("deltas", {}).get("fd_count", 0),
                socket_fd=result.get("deltas", {}).get("socket_fd_count", 0),
            )
        )

    lines.append("")
    lines.append("## Violations")
    lines.append("")
    violations = payload.get("violations", [])
    if isinstance(violations, list) and violations:
        for violation in violations:
            lines.append(f"- {violation}")
    else:
        lines.append("- none")

    summary = payload.get("summary", {})
    lines.append("")
    lines.append("## Totals")
    lines.append("")
    lines.append(f"- Modes evaluated: `{summary.get('total_modes', 0)}`")
    lines.append(f"- Passed modes: `{summary.get('passed_modes', 0)}`")
    lines.append(f"- Failed modes: `{summary.get('failed_modes', 0)}`")
    lines.append(f"- Status: `{summary.get('status', 'fail')}`")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 10M long-run soak artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--binary", default="build/boomhauer")
    parser.add_argument(
        "--thresholds",
        default="tests/fixtures/performance/phase10m_soak_thresholds.json",
    )
    parser.add_argument("--output-dir", default="build/release_confidence/phase10m/soak")
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    binary = (repo_root / args.binary).resolve()
    thresholds_path = (repo_root / args.thresholds).resolve()
    output_dir = Path(args.output_dir).resolve()

    if not binary.exists():
        raise SystemExit(f"binary not found: {binary}")

    thresholds = load_json(thresholds_path)
    if thresholds.get("version") != THRESHOLD_VERSION:
        raise SystemExit("phase10m soak threshold fixture version mismatch")

    modes = thresholds.get("modes", ["concurrent", "serialized"])
    if not isinstance(modes, list) or not modes:
        raise SystemExit("threshold fixture must define non-empty modes")

    results: List[Dict[str, Any]] = []
    violations: List[str] = []
    for mode in modes:
        if not isinstance(mode, str) or mode not in {"concurrent", "serialized"}:
            violations.append(f"invalid mode in fixture: {mode}")
            continue
        result = run_mode(binary, mode, thresholds)
        results.append(result)
        for violation in result.get("violations", []):
            violations.append(f"mode {mode}: {violation}")

    passed_modes = sum(1 for result in results if result.get("status") == "pass")
    failed_modes = len(results) - passed_modes
    status = "pass" if failed_modes == 0 and not violations else "fail"

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": git_commit(repo_root),
        "threshold_fixture": str(thresholds_path),
        "threshold_fixture_version": thresholds.get("version", ""),
        "thresholds": thresholds,
        "results": results,
        "violations": violations,
        "summary": {
            "total_modes": len(results),
            "passed_modes": passed_modes,
            "failed_modes": failed_modes,
            "status": status,
        },
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    write_json(output_dir / "soak_results.json", payload)
    (output_dir / "phase10m_soak_summary.md").write_text(
        render_markdown(payload, output_dir),
        encoding="utf-8",
    )

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": payload["commit"],
        "status": status,
        "artifacts": [
            "soak_results.json",
            "phase10m_soak_summary.md",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase10m-soak: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
