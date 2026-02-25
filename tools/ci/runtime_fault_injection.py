#!/usr/bin/env python3
"""Phase 9I runtime fault-injection harness for high-risk seams."""

from __future__ import annotations

import argparse
import base64
import json
import os
import random
import socket
import struct
import subprocess
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple


FAULT_VERSION = "phase9i-fault-injection-v1"
DEFAULT_SCENARIO_FIXTURE = "tests/fixtures/fault_injection/phase9i_fault_scenarios.json"
RECOVERABLE_RESTART_SIGNATURES = {
    "timeout",
    "connection_refused",
    "connection_reset",
    "connection_closed",
    "bad_status_line",
}


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


def normalize_failure_signature(error: BaseException) -> str:
    message = str(error).lower()
    if "timed out" in message:
        return "timeout"
    if "connection refused" in message:
        return "connection_refused"
    if "connection reset" in message:
        return "connection_reset"
    if "closed before headers" in message:
        return "connection_closed"
    if "connection closed" in message or "remote end closed" in message:
        return "connection_closed"
    if "bad status line" in message:
        return "bad_status_line"
    if "websocket" in message and "invalid" in message:
        return "invalid_websocket_response"
    return "unexpected_error"


def allocate_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def recv_exact(sock: socket.socket, size: int) -> bytes:
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise RuntimeError("connection closed")
        data += chunk
    return data


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
            body = urllib.request.urlopen(
                f"http://127.0.0.1:{port}/healthz", timeout=1.5
            ).read().decode("utf-8")
            if body == "ok\n":
                return
            last_error = f"unexpected health body: {body!r}"
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(0.2)
    raise RuntimeError(f"server failed readiness probe: {last_error}")


def assert_health(port: int, retries: int = 8) -> None:
    last_error = ""
    for _ in range(retries):
        try:
            body = urllib.request.urlopen(
                f"http://127.0.0.1:{port}/healthz", timeout=1.0
            ).read().decode("utf-8")
            if body == "ok\n":
                return
            last_error = f"unexpected health body: {body!r}"
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(0.05)
    raise RuntimeError(f"health check failed after fault injection: {last_error}")


def server_command(binary: str, mode: str, port: int) -> List[str]:
    if mode == "serialized":
        return [binary, "--env", "production", "--port", str(port)]
    return [binary, "--port", str(port)]


def start_server(binary: str, mode: str, port: int) -> subprocess.Popen[str]:
    command = server_command(binary, mode, port)
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


def stop_server(process: Optional[subprocess.Popen[str]]) -> None:
    if process is None:
        return
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def abrupt_disconnect(sock: socket.socket) -> None:
    try:
        sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    sock.close()


def ws_connect(port: int, path: str) -> socket.socket:
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    ).encode("utf-8")
    sock = socket.create_connection(("127.0.0.1", port), timeout=5)
    sock.settimeout(5)
    sock.sendall(request)
    response = b""
    while b"\r\n\r\n" not in response:
        chunk = sock.recv(4096)
        if not chunk:
            break
        response += chunk
    if b"101 Switching Protocols" not in response:
        raise RuntimeError(
            f"invalid websocket response: {response.decode('utf-8', 'replace')}"
        )
    return sock


def ws_send_text(sock: socket.socket, text: str) -> None:
    payload = text.encode("utf-8")
    mask = os.urandom(4)
    header = bytearray([0x81])
    length = len(payload)
    if length <= 125:
        header.append(0x80 | length)
    elif length <= 65535:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", length))
    masked = bytes(payload[i] ^ mask[i & 3] for i in range(length))
    sock.sendall(bytes(header) + mask + masked)


def ws_recv_text(sock: socket.socket) -> str:
    b1, b2 = recv_exact(sock, 2)
    opcode = b1 & 0x0F
    length = b2 & 0x7F
    masked = (b2 & 0x80) != 0
    if length == 126:
        length = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(sock, 8))[0]
    mask_key = recv_exact(sock, 4) if masked else b""
    payload = recv_exact(sock, length)
    if masked:
        payload = bytes(payload[i] ^ mask_key[i & 3] for i in range(length))
    if opcode != 0x1:
        raise RuntimeError(f"unexpected websocket opcode {opcode}")
    return payload.decode("utf-8")


def send_partial_http_request(port: int, disconnect_offset: int, delay_seconds: float) -> Dict[str, Any]:
    request = (
        f"POST /api/sleep?ms=35 HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 12\r\n"
    ).encode("utf-8")
    cutoff = max(1, min(disconnect_offset, len(request) - 1))
    sock = socket.create_connection(("127.0.0.1", port), timeout=3)
    sock.settimeout(3)
    try:
        sock.sendall(request[:cutoff])
        time.sleep(delay_seconds)
    finally:
        abrupt_disconnect(sock)
    return {
        "disconnect_offset": cutoff,
        "fault_signature": "connection_closed",
    }


def send_delayed_http_request(port: int, rng: random.Random, probe_midstream: bool) -> Dict[str, Any]:
    request = (
        f"GET /healthz HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "Connection: close\r\n\r\n"
    ).encode("utf-8")
    chunk_sizes: List[int] = []
    delay_samples: List[float] = []
    mid_probe_sent = False
    midpoint = len(request) // 2

    sock = socket.create_connection(("127.0.0.1", port), timeout=4)
    sock.settimeout(4)
    try:
        cursor = 0
        while cursor < len(request):
            chunk = rng.randint(1, 4)
            end = min(len(request), cursor + chunk)
            sock.sendall(request[cursor:end])
            chunk_sizes.append(end - cursor)
            cursor = end
            if probe_midstream and not mid_probe_sent and cursor >= midpoint:
                assert_health(port)
                mid_probe_sent = True
            delay = rng.uniform(0.001, 0.006)
            delay_samples.append(round(delay, 6))
            time.sleep(delay)

        status, _, body = read_http_response(sock)
        if "200" not in status or body != b"ok\n":
            raise RuntimeError(f"unexpected delayed-write response: {status} body={body!r}")
    finally:
        sock.close()

    return {
        "chunks_sent": len(chunk_sizes),
        "chunk_sizes": chunk_sizes,
        "delay_samples": delay_samples,
    }


def perform_socket_churn(port: int, rng: random.Random) -> Dict[str, Any]:
    attempts = 24 + rng.randint(0, 8)
    abrupt = 0
    graceful = 0
    for _ in range(attempts):
        sock = socket.create_connection(("127.0.0.1", port), timeout=3)
        sock.settimeout(3)
        if rng.random() < 0.4:
            abrupt += 1
            abrupt_disconnect(sock)
            continue

        graceful += 1
        request = (
            f"GET /healthz HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{port}\r\n"
            "Connection: close\r\n\r\n"
        ).encode("utf-8")
        try:
            sock.sendall(request)
            status, _, body = read_http_response(sock)
            if "200" not in status or body != b"ok\n":
                raise RuntimeError(f"socket churn health response mismatch: {status} body={body!r}")
        finally:
            sock.close()
    return {
        "attempts": attempts,
        "abrupt_disconnects": abrupt,
        "graceful_roundtrips": graceful,
    }


def send_malformed_websocket_upgrade(port: int) -> Dict[str, Any]:
    request = (
        f"GET /ws/echo HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Version: 12\r\n\r\n"
    ).encode("utf-8")
    sock = socket.create_connection(("127.0.0.1", port), timeout=4)
    sock.settimeout(4)
    try:
        sock.sendall(request)
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response += chunk
    finally:
        sock.close()

    lines = response.decode("utf-8", "replace").split("\r\n")
    status_line = lines[0] if lines else ""
    if "HTTP/1.1" not in status_line and "HTTP/1.0" not in status_line:
        raise RuntimeError(f"malformed websocket upgrade did not return HTTP status line: {status_line!r}")
    accepted_upgrade = "101" in status_line
    return {
        "status_line": status_line,
        "accepted_upgrade": accepted_upgrade,
        "fault_signature": "malformed_upgrade_accepted"
        if accepted_upgrade
        else "invalid_websocket_response",
    }


def send_partial_websocket_frame_then_disconnect(port: int, rng: random.Random) -> Dict[str, Any]:
    sock = ws_connect(port, "/ws/echo")
    payload = b"phase9i-partial-frame"
    mask = os.urandom(4)
    masked = bytes(payload[i] ^ mask[i & 3] for i in range(len(payload)))
    frame = bytes([0x81, 0x80 | len(payload)]) + mask + masked
    cutoff = rng.randint(2, len(frame) - 1)
    try:
        sock.sendall(frame[:cutoff])
    finally:
        abrupt_disconnect(sock)
    return {
        "frame_length": len(frame),
        "sent_bytes_before_disconnect": cutoff,
        "fault_signature": "connection_closed",
    }


def run_with_server(binary: str, mode: str, callback: Callable[[int], Dict[str, Any]]) -> Dict[str, Any]:
    port = allocate_free_port()
    server = start_server(binary, mode, port)
    try:
        result = callback(port)
        assert_health(port)
        return result
    finally:
        stop_server(server)


def scenario_http_partial_request_disconnect(binary: str, mode: str, rng: random.Random) -> Dict[str, Any]:
    def runner(port: int) -> Dict[str, Any]:
        details = send_partial_http_request(
            port=port,
            disconnect_offset=rng.randint(24, 72),
            delay_seconds=rng.uniform(0.002, 0.012),
        )
        assert_health(port)
        return details

    return run_with_server(binary, mode, runner)


def scenario_http_delayed_write_sequence(binary: str, mode: str, rng: random.Random) -> Dict[str, Any]:
    probe_midstream = mode == "concurrent"
    return run_with_server(
        binary,
        mode,
        lambda port: send_delayed_http_request(port, rng, probe_midstream=probe_midstream),
    )


def scenario_socket_churn_burst(binary: str, mode: str, rng: random.Random) -> Dict[str, Any]:
    return run_with_server(binary, mode, lambda port: perform_socket_churn(port, rng))


def scenario_websocket_malformed_upgrade(binary: str, mode: str, rng: random.Random) -> Dict[str, Any]:
    _ = rng  # scenario has deterministic malformed handshake payload.
    return run_with_server(binary, mode, lambda port: send_malformed_websocket_upgrade(port))


def scenario_websocket_partial_frame_disconnect(binary: str, mode: str, rng: random.Random) -> Dict[str, Any]:
    def runner(port: int) -> Dict[str, Any]:
        details = send_partial_websocket_frame_then_disconnect(port, rng)
        recovery = ws_connect(port, "/ws/echo")
        try:
            ws_send_text(recovery, "phase9i-recovery")
            echoed = ws_recv_text(recovery)
            if echoed != "phase9i-recovery":
                raise RuntimeError("websocket recovery probe mismatch after partial-frame disconnect")
        finally:
            recovery.close()
        return details

    return run_with_server(binary, mode, runner)


def scenario_runtime_restart_overlap(binary: str, mode: str, rng: random.Random) -> Dict[str, Any]:
    port = allocate_free_port()
    process: Optional[subprocess.Popen[str]] = None
    stop_event = threading.Event()
    non_transient: List[str] = []
    transient_count = 0
    lock = threading.Lock()

    def load_loop() -> None:
        nonlocal transient_count
        while not stop_event.is_set():
            for path in ("/healthz", "/api/sleep?ms=30"):
                if stop_event.is_set():
                    break
                try:
                    urllib.request.urlopen(
                        f"http://127.0.0.1:{port}{path}", timeout=1.2
                    ).read()
                except Exception as exc:  # noqa: BLE001
                    signature = normalize_failure_signature(exc)
                    if signature in RECOVERABLE_RESTART_SIGNATURES:
                        with lock:
                            transient_count += 1
                    elif not stop_event.is_set():
                        non_transient.append(str(exc))
                time.sleep(0.01)

    worker = threading.Thread(target=load_loop)
    try:
        process = start_server(binary, mode, port)
        worker.start()
        time.sleep(rng.uniform(0.14, 0.22))
        stop_server(process)
        process = start_server(binary, mode, port)
        assert_health(port)
        stop_event.set()
        worker.join(timeout=6)
        if non_transient:
            raise RuntimeError("; ".join(non_transient))
        assert_health(port)
        return {
            "port": port,
            "transient_fault_count": transient_count,
        }
    finally:
        stop_event.set()
        worker.join(timeout=6)
        stop_server(process)


SCENARIO_RUNNERS: Dict[str, Callable[[str, str, random.Random], Dict[str, Any]]] = {
    "http_partial_request_disconnect": scenario_http_partial_request_disconnect,
    "http_delayed_write_sequence": scenario_http_delayed_write_sequence,
    "socket_churn_burst": scenario_socket_churn_burst,
    "websocket_malformed_upgrade": scenario_websocket_malformed_upgrade,
    "websocket_partial_frame_disconnect": scenario_websocket_partial_frame_disconnect,
    "runtime_restart_overlap": scenario_runtime_restart_overlap,
}


def render_markdown(
    generated_at: str,
    commit: str,
    seed: int,
    iterations: int,
    selected_modes: List[str],
    selected_scenarios: List[Dict[str, str]],
    results: List[Dict[str, Any]],
    summary: Dict[str, Any],
    output_dir: Path,
) -> str:
    lines: List[str] = []
    lines.append("# Phase 9I Fault Injection Summary")
    lines.append("")
    lines.append(f"Generated at: `{generated_at}`")
    lines.append(f"Git commit: `{commit}`")
    lines.append(f"Seed: `{seed}`")
    lines.append(f"Iterations per mode: `{iterations}`")
    lines.append(f"Modes: `{', '.join(selected_modes)}`")
    lines.append("")
    lines.append("## Scenario Matrix")
    lines.append("")
    lines.append("| Scenario | Seam | Status | Mode | Iteration | Failure Signature |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for result in results:
        failure_signature = result.get("failure_signature") or ""
        lines.append(
            "| {scenario_id} | {seam} | {status} | {mode} | {iteration} | {failure} |".format(
                scenario_id=result["scenario_id"],
                seam=result["seam"],
                status=result["status"],
                mode=result["mode"],
                iteration=result["iteration"],
                failure=failure_signature,
            )
        )

    lines.append("")
    lines.append("## Coverage")
    lines.append("")
    for scenario in selected_scenarios:
        lines.append(f"- `{scenario['id']}` => seam `{scenario['seam']}`")

    lines.append("")
    lines.append("## Totals")
    lines.append("")
    lines.append(f"- Total scenario runs: `{summary['total']}`")
    lines.append(f"- Passed: `{summary['passed']}`")
    lines.append(f"- Failed: `{summary['failed']}`")
    lines.append("")
    lines.append("Failure signatures:")
    if summary["failure_signatures"]:
        for key, value in sorted(summary["failure_signatures"].items()):
            lines.append(f"- `{key}`: `{value}`")
    else:
        lines.append("- none")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def parse_modes(raw_modes: str) -> List[str]:
    modes = [value.strip() for value in raw_modes.split(",") if value.strip()]
    for mode in modes:
        if mode not in {"concurrent", "serialized"}:
            raise ValueError(f"unsupported mode '{mode}'")
    if not modes:
        raise ValueError("at least one mode is required")
    return modes


def select_scenarios(
    fixture_payload: Dict[str, Any], requested: Optional[str]
) -> Tuple[List[Dict[str, str]], bool]:
    raw_scenarios = fixture_payload.get("scenarios")
    if not isinstance(raw_scenarios, list):
        raise ValueError("fault scenario fixture must include 'scenarios' array")

    scenarios: List[Dict[str, str]] = []
    for item in raw_scenarios:
        if not isinstance(item, dict):
            continue
        scenario_id = item.get("id")
        seam = item.get("seam")
        description = item.get("description", "")
        if not isinstance(scenario_id, str) or not isinstance(seam, str):
            continue
        scenarios.append(
            {
                "id": scenario_id,
                "seam": seam,
                "description": str(description),
            }
        )

    if not scenarios:
        raise ValueError("fault scenario fixture did not define any valid scenarios")

    if requested is None or requested.strip() == "":
        return scenarios, False

    requested_ids = [value.strip() for value in requested.split(",") if value.strip()]
    known = {item["id"] for item in scenarios}
    for scenario_id in requested_ids:
        if scenario_id not in known:
            raise ValueError(f"unknown requested scenario '{scenario_id}'")

    selected: List[Dict[str, str]] = []
    for scenario_id in requested_ids:
        selected.append(next(item for item in scenarios if item["id"] == scenario_id))
    return selected, True


def run_fault_matrix(
    binary: str,
    modes: List[str],
    scenarios: List[Dict[str, str]],
    seed: int,
    iterations: int,
) -> List[Dict[str, Any]]:
    master_rng = random.Random(seed)
    results: List[Dict[str, Any]] = []
    for mode in modes:
        for iteration in range(1, iterations + 1):
            for scenario in scenarios:
                scenario_id = scenario["id"]
                runner = SCENARIO_RUNNERS.get(scenario_id)
                if runner is None:
                    raise ValueError(f"scenario runner missing for '{scenario_id}'")
                scenario_seed = master_rng.randrange(1, 2**31 - 1)
                scenario_rng = random.Random(scenario_seed)
                started = time.monotonic()
                record: Dict[str, Any] = {
                    "scenario_id": scenario_id,
                    "seam": scenario["seam"],
                    "mode": mode,
                    "iteration": iteration,
                    "seed": scenario_seed,
                }
                try:
                    details = runner(binary, mode, scenario_rng)
                    record["status"] = "pass"
                    record["details"] = details
                except Exception as exc:  # noqa: BLE001
                    record["status"] = "fail"
                    record["failure_signature"] = normalize_failure_signature(exc)
                    record["failure_message"] = str(exc)
                record["duration_ms"] = int((time.monotonic() - started) * 1000)
                results.append(record)
    return results


def summarize_results(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    total = len(results)
    passed = sum(1 for item in results if item["status"] == "pass")
    failed = total - passed
    failure_signatures: Dict[str, int] = {}
    seam_counts: Dict[str, int] = {}
    for item in results:
        seam = str(item.get("seam", ""))
        seam_counts[seam] = seam_counts.get(seam, 0) + 1
        signature = item.get("failure_signature")
        if isinstance(signature, str) and signature:
            failure_signatures[signature] = failure_signatures.get(signature, 0) + 1
    return {
        "total": total,
        "passed": passed,
        "failed": failed,
        "failure_signatures": failure_signatures,
        "seam_counts": seam_counts,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Phase 9I runtime fault-injection scenarios")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--binary", required=True, help="Path to boomhauer binary")
    parser.add_argument("--output-dir", default="build/release_confidence/phase9i")
    parser.add_argument("--seed", type=int, default=9011)
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--modes", default="concurrent,serialized")
    parser.add_argument(
        "--scenario-fixture",
        default=DEFAULT_SCENARIO_FIXTURE,
        help="Fixture describing fault scenarios and seam mapping",
    )
    parser.add_argument(
        "--scenarios",
        default="",
        help="Optional comma-separated subset of scenario ids",
    )
    args = parser.parse_args()

    if args.iterations < 1:
        raise ValueError("--iterations must be >= 1")

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    fixture_path = (repo_root / args.scenario_fixture).resolve()
    fixture_payload = load_json(fixture_path)
    scenarios, selected_subset = select_scenarios(fixture_payload, args.scenarios)
    modes = parse_modes(args.modes)
    binary = str((repo_root / args.binary).resolve())

    results = run_fault_matrix(binary, modes, scenarios, args.seed, args.iterations)
    summary = summarize_results(results)

    required_seams = {item["seam"] for item in scenarios}
    executed_seams = {item["seam"] for item in results}
    missing_seams = sorted(required_seams - executed_seams)
    if missing_seams and not selected_subset:
        summary["failed"] += len(missing_seams)
        for seam in missing_seams:
            summary["failure_signatures"][f"missing_seam_{seam}"] = 1

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    commit = git_commit(repo_root)

    payload = {
        "version": FAULT_VERSION,
        "generated_at": generated_at,
        "commit": commit,
        "seed": args.seed,
        "iterations": args.iterations,
        "modes": modes,
        "binary": binary,
        "scenario_fixture_version": fixture_payload.get("version", ""),
        "scenarios": scenarios,
        "results": results,
        "summary": summary,
        "selected_subset": selected_subset,
        "missing_seams": missing_seams,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    write_json(output_dir / "fault_injection_results.json", payload)

    markdown = render_markdown(
        generated_at=generated_at,
        commit=commit,
        seed=args.seed,
        iterations=args.iterations,
        selected_modes=modes,
        selected_scenarios=scenarios,
        results=results,
        summary=summary,
        output_dir=output_dir,
    )
    (output_dir / "phase9i_fault_injection_summary.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": FAULT_VERSION,
        "generated_at": generated_at,
        "commit": commit,
        "artifacts": [
            "fault_injection_results.json",
            "phase9i_fault_injection_summary.md",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase9i-fault-injection: generated artifacts in {output_dir}")
    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
