#!/usr/bin/env python3
"""Phase 10M protocol adversarial backend probe."""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List


VERSION = "phase10m-protocol-adversarial-v1"


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


def allocate_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def health_probe(port: int) -> Dict[str, Any]:
    payload = (
        "GET /healthz HTTP/1.1\r\n"
        "Host: 127.0.0.1\r\n"
        "Connection: close\r\n\r\n"
    ).encode("utf-8")
    return send_raw_request(port, payload)


def wait_ready(port: int, timeout_seconds: float = 12.0) -> None:
    deadline = time.time() + timeout_seconds
    last_error = ""
    while time.time() < deadline:
        try:
            response = health_probe(port)
            if int(response.get("status_code", 0)) == 200:
                return
            last_error = f"unexpected health status: {response.get('status_line', '')}"
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(0.15)
    raise RuntimeError(f"server failed readiness probe: {last_error}")


def assert_health(port: int, retries: int = 8) -> None:
    last_error = ""
    for _ in range(retries):
        try:
            response = health_probe(port)
            if int(response.get("status_code", 0)) == 200:
                return
            last_error = f"unexpected health status: {response.get('status_line', '')}"
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(0.08)
    raise RuntimeError(f"health check failed after adversarial request: {last_error}")


def read_status_line(sock: socket.socket) -> str:
    data = b""
    while b"\r\n" not in data and len(data) < 16384:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    if b"\r\n" not in data:
        raise RuntimeError("missing status line")
    return data.split(b"\r\n", 1)[0].decode("ascii", "replace")


def status_code_from_line(status_line: str) -> int:
    parts = status_line.split(" ")
    if len(parts) < 2:
        return 0
    try:
        return int(parts[1])
    except Exception:
        return 0


def send_raw_request(port: int, payload: bytes) -> Dict[str, Any]:
    sock = socket.create_connection(("127.0.0.1", port), timeout=4)
    sock.settimeout(4)
    try:
        sock.sendall(payload)
        status_line = read_status_line(sock)
    finally:
        try:
            sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        sock.close()
    return {
        "status_line": status_line,
        "status_code": status_code_from_line(status_line),
    }


def server_env(base_env: Dict[str, str], backend: str, limits: Dict[str, Any]) -> Dict[str, str]:
    env = dict(base_env)
    env["ARLEN_HTTP_PARSER_BACKEND"] = backend
    if "maxRequestLineBytes" in limits:
        env["ARLEN_MAX_REQUEST_LINE_BYTES"] = str(int(limits["maxRequestLineBytes"]))
    if "maxHeaderBytes" in limits:
        env["ARLEN_MAX_HEADER_BYTES"] = str(int(limits["maxHeaderBytes"]))
    if "maxBodyBytes" in limits:
        env["ARLEN_MAX_BODY_BYTES"] = str(int(limits["maxBodyBytes"]))
    return env


def start_server(binary: Path, backend: str, limits: Dict[str, Any], base_env: Dict[str, str]) -> tuple[int, subprocess.Popen[str]]:
    port = allocate_free_port()
    process = subprocess.Popen(
        [str(binary), "--port", str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=server_env(base_env, backend, limits),
    )
    try:
        wait_ready(port)
    except Exception:
        stop_server(process)
        raise
    return port, process


def stop_server(process: subprocess.Popen[str] | None) -> None:
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


def make_markdown(payload: Dict[str, Any], output_dir: Path) -> str:
    lines: List[str] = []
    lines.append("# Phase 10M Protocol Adversarial Probe")
    lines.append("")
    lines.append(f"Generated at: `{payload['generated_at']}`")
    lines.append(f"Git commit: `{payload['commit']}`")
    lines.append(f"Fixture version: `{payload.get('fixture_version', '')}`")
    lines.append("")
    lines.append("| Backend | Case | Expected | Observed | Status |")
    lines.append("| --- | --- | --- | --- | --- |")
    for result in payload.get("results", []):
        lines.append(
            "| {backend} | {case_id} | {expected} | {observed} | {status} |".format(
                backend=result.get("backend", ""),
                case_id=result.get("case_id", ""),
                expected=result.get("expected_status", ""),
                observed=result.get("observed_status", ""),
                status=result.get("status", ""),
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
    summary = payload.get("summary", {})
    lines.append("## Totals")
    lines.append("")
    lines.append(f"- Total probes: `{summary.get('total', 0)}`")
    lines.append(f"- Passed: `{summary.get('passed', 0)}`")
    lines.append(f"- Failed: `{summary.get('failed', 0)}`")
    lines.append(f"- Status: `{summary.get('status', 'fail')}`")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


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


def main() -> int:
    parser = argparse.ArgumentParser(description="Run protocol adversarial probe against parser backends")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--binary", default="build/boomhauer")
    parser.add_argument(
        "--fixture",
        default="tests/fixtures/protocol/phase10m_protocol_adversarial_cases.json",
    )
    parser.add_argument("--output-dir", default="build/release_confidence/phase10m/protocol_adversarial")
    parser.add_argument("--backends", default="llhttp,legacy")
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    binary = (repo_root / args.binary).resolve()
    fixture = (repo_root / args.fixture).resolve()
    output_dir = Path(args.output_dir).resolve()

    if not binary.exists():
        raise SystemExit(f"binary not found: {binary}")

    fixture_payload = load_json(fixture)
    if fixture_payload.get("version") != VERSION:
        raise SystemExit("protocol adversarial fixture version mismatch")

    raw_backends = [item.strip() for item in args.backends.split(",") if item.strip()]
    if not raw_backends:
        raise SystemExit("at least one backend is required")

    cases = fixture_payload.get("cases")
    if not isinstance(cases, list) or not cases:
        raise SystemExit("fixture must include non-empty cases array")

    limits = fixture_payload.get("limits", {})
    if not isinstance(limits, dict):
        limits = {}

    base_env = dict(os.environ)
    results: List[Dict[str, Any]] = []
    violations: List[str] = []

    for backend in raw_backends:
        port = 0
        process: subprocess.Popen[str] | None = None
        try:
            port, process = start_server(binary, backend, limits, base_env)
            for case in cases:
                if not isinstance(case, dict):
                    continue
                case_id = str(case.get("id", ""))
                request = case.get("request")
                expected_status = int(case.get("expectedStatus", 0))
                if not case_id or not isinstance(request, str) or expected_status <= 0:
                    violations.append(f"invalid fixture case: {case}")
                    continue

                record: Dict[str, Any] = {
                    "backend": backend,
                    "case_id": case_id,
                    "expected_status": expected_status,
                    "observed_status": 0,
                    "status": "fail",
                    "status_line": "",
                    "error": "",
                }
                try:
                    response = send_raw_request(port, request.encode("utf-8"))
                    record["status_line"] = response["status_line"]
                    record["observed_status"] = int(response["status_code"])
                    if record["observed_status"] == expected_status:
                        record["status"] = "pass"
                    else:
                        record["error"] = "status_mismatch"
                        violations.append(
                            f"backend {backend} case {case_id}: expected {expected_status}, got {record['observed_status']}"
                        )
                except Exception as exc:  # noqa: BLE001
                    record["error"] = str(exc)
                    violations.append(f"backend {backend} case {case_id}: exception {exc}")

                results.append(record)
                try:
                    assert_health(port)
                except Exception as exc:  # noqa: BLE001
                    violations.append(f"backend {backend} case {case_id}: health recovery failed ({exc})")
        finally:
            stop_server(process)

    total = len(results)
    passed = sum(1 for item in results if item.get("status") == "pass")
    failed = total - passed
    status = "pass" if failed == 0 and not violations else "fail"

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": git_commit(repo_root),
        "fixture": str(fixture),
        "fixture_version": fixture_payload.get("version", ""),
        "limits": limits,
        "backends": raw_backends,
        "results": results,
        "violations": violations,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": failed,
            "status": status,
        },
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    write_json(output_dir / "protocol_adversarial_results.json", payload)
    markdown = make_markdown(payload, output_dir)
    (output_dir / "phase10m_protocol_adversarial.md").write_text(markdown, encoding="utf-8")
    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": payload["commit"],
        "status": status,
        "artifacts": [
            "protocol_adversarial_results.json",
            "phase10m_protocol_adversarial.md",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase10m-protocol-adversarial: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
