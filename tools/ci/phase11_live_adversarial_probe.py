#!/usr/bin/env python3
"""Sustained mixed hostile-traffic probe for Phase 11."""

from __future__ import annotations

import argparse
import base64
import errno
import os
import socket
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple

from protocol_adversarial_probe import (
    assert_health,
    git_commit,
    send_raw_request,
    start_server,
    stop_server,
    write_json,
)


VERSION = "phase11-live-adversarial-v1"
VALID_WS_KEY = base64.b64encode(b"phase11-test-key").decode("ascii")


def read_http_head(sock: socket.socket) -> Tuple[str, bytes]:
    data = b""
    while b"\r\n\r\n" not in data and len(data) < 32768:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    if b"\r\n\r\n" not in data:
        raise RuntimeError("incomplete HTTP response head")
    head, remainder = data.split(b"\r\n\r\n", 1)
    status_line = head.split(b"\r\n", 1)[0].decode("ascii", "replace")
    return status_line, remainder


def websocket_handshake(port: int, origin: str) -> socket.socket:
    request = (
        "GET /ws/echo HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {VALID_WS_KEY}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Origin: {origin}\r\n\r\n"
    ).encode("utf-8")
    sock = socket.create_connection(("127.0.0.1", port), timeout=3)
    sock.settimeout(3)
    sock.sendall(request)
    status_line, _ = read_http_head(sock)
    if " 101 " not in status_line:
        sock.close()
        raise RuntimeError(f"unexpected websocket handshake status: {status_line}")
    return sock


def expect_close_frame_or_disconnect(sock: socket.socket) -> None:
    try:
        chunk = sock.recv(4096)
    except socket.timeout as exc:
        raise RuntimeError("websocket connection remained open past deadline") from exc
    except OSError as exc:
        if exc.errno in {errno.ECONNRESET, errno.EPIPE}:
            return
        raise RuntimeError(f"websocket closed with unexpected socket error: {exc}") from exc

    if chunk == b"":
        return
    if (chunk[0] & 0x0F) == 0x08:
        return
    raise RuntimeError(f"unexpected websocket payload after hostile frame: {chunk[:8]!r}")


def case_nominal_http(port: int) -> Dict[str, Any]:
    response = send_raw_request(
        port,
        b"GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
    )
    observed = int(response.get("status_code", 0))
    return {
        "case_id": "nominal_http",
        "expected": 200,
        "observed": observed,
        "detail": str(response.get("status_line", "")),
        "status": "pass" if observed == 200 else "fail",
    }


def case_duplicate_content_length(port: int) -> Dict[str, Any]:
    response = send_raw_request(
        port,
        b"POST /healthz HTTP/1.1\r\n"
        b"Host: 127.0.0.1\r\n"
        b"Content-Length: 5\r\n"
        b"Content-Length: 5\r\n\r\n"
        b"hello",
    )
    observed = int(response.get("status_code", 0))
    return {
        "case_id": "duplicate_content_length",
        "expected": 400,
        "observed": observed,
        "detail": str(response.get("status_line", "")),
        "status": "pass" if observed == 400 else "fail",
    }


def case_invalid_websocket_version(port: int) -> Dict[str, Any]:
    response = send_raw_request(
        port,
        (
            "GET /ws/echo HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {VALID_WS_KEY}\r\n"
            "Sec-WebSocket-Version: 12\r\n"
            "Origin: https://allowed.example\r\n\r\n"
        ).encode("utf-8"),
    )
    observed = int(response.get("status_code", 0))
    return {
        "case_id": "websocket_invalid_version",
        "expected": 400,
        "observed": observed,
        "detail": str(response.get("status_line", "")),
        "status": "pass" if observed == 400 else "fail",
    }


def case_blocked_websocket_origin(port: int) -> Dict[str, Any]:
    response = send_raw_request(
        port,
        (
            "GET /ws/echo HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {VALID_WS_KEY}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "Origin: https://blocked.example\r\n\r\n"
        ).encode("utf-8"),
    )
    observed = int(response.get("status_code", 0))
    return {
        "case_id": "websocket_blocked_origin",
        "expected": 403,
        "observed": observed,
        "detail": str(response.get("status_line", "")),
        "status": "pass" if observed == 403 else "fail",
    }


def case_unmasked_websocket_frame(port: int) -> Dict[str, Any]:
    sock = websocket_handshake(port, "https://allowed.example")
    try:
        try:
            sock.sendall(b"\x81\x05hello")
        except OSError as exc:
            if exc.errno not in {errno.ECONNRESET, errno.EPIPE}:
                raise
        expect_close_frame_or_disconnect(sock)
        return {
            "case_id": "websocket_unmasked_frame",
            "expected": "connection_close",
            "observed": "connection_close",
            "detail": "server closed after unmasked frame",
            "status": "pass",
        }
    except Exception as exc:  # noqa: BLE001
        return {
            "case_id": "websocket_unmasked_frame",
            "expected": "connection_close",
            "observed": "open",
            "detail": str(exc),
            "status": "fail",
        }
    finally:
        try:
            sock.close()
        except OSError:
            pass


def make_markdown(payload: Dict[str, Any], output_dir: Path) -> str:
    lines: List[str] = []
    lines.append("# Phase 11 Live Adversarial Probe")
    lines.append("")
    lines.append(f"Generated at: `{payload['generated_at']}`")
    lines.append(f"Git commit: `{payload['commit']}`")
    lines.append("")
    lines.append("| Mode | Round | Case | Expected | Observed | Status |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for result in payload.get("results", []):
        lines.append(
            "| {mode} | {round} | {case_id} | {expected} | {observed} | {status} |".format(
                mode=result.get("mode", ""),
                round=result.get("round", 0),
                case_id=result.get("case_id", ""),
                expected=result.get("expected", ""),
                observed=result.get("observed", ""),
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
    lines.append(f"- Total cases: `{summary.get('total', 0)}`")
    lines.append(f"- Passed: `{summary.get('passed', 0)}`")
    lines.append(f"- Failed: `{summary.get('failed', 0)}`")
    lines.append(f"- Status: `{summary.get('status', 'fail')}`")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Phase 11 live hostile-traffic probe")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--binary", default="build/boomhauer")
    parser.add_argument("--output-dir", default="build/release_confidence/phase11/live_adversarial")
    parser.add_argument("--modes", default="serialized,concurrent")
    parser.add_argument("--rounds", type=int, default=2)
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    binary = (repo_root / args.binary).resolve()
    output_dir = Path(args.output_dir).resolve()
    modes = [item.strip() for item in str(args.modes).split(",") if item.strip()]
    if not modes:
        raise SystemExit("at least one dispatch mode is required")
    if not binary.exists():
        raise SystemExit(f"binary not found: {binary}")

    base_env = dict(os.environ)
    base_env.setdefault("ARLEN_WEBSOCKET_ALLOWED_ORIGINS", "https://allowed.example")
    base_env.setdefault("ARLEN_WEBSOCKET_READ_TIMEOUT_MS", "250")

    results: List[Dict[str, Any]] = []
    violations: List[str] = []
    cases = [
        lambda port: case_nominal_http(port),
        lambda port: case_duplicate_content_length(port),
        lambda port: case_invalid_websocket_version(port),
        lambda port: case_blocked_websocket_origin(port),
        lambda port: case_unmasked_websocket_frame(port),
    ]

    for mode in modes:
        port = 0
        process = None
        mode_env = dict(base_env)
        mode_env["ARLEN_REQUEST_DISPATCH_MODE"] = mode
        try:
            port, process = start_server(binary, "llhttp", {}, mode_env)
            for round_index in range(1, max(1, args.rounds) + 1):
                for case in cases:
                    result = case(port)
                    result["mode"] = mode
                    result["round"] = round_index
                    results.append(result)
                    if result.get("status") != "pass":
                        violations.append(
                            f"mode {mode} round {round_index} case {result.get('case_id')}: {result.get('detail')}"
                        )
                try:
                    assert_health(port)
                except Exception as exc:  # noqa: BLE001
                    violations.append(f"mode {mode} round {round_index}: health recovery failed ({exc})")
        finally:
            stop_server(process)

    total = len(results)
    passed = sum(1 for item in results if item.get("status") == "pass")
    failed = total - passed
    status = "pass" if failed == 0 and not violations else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    payload: Dict[str, Any] = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": git_commit(repo_root),
        "modes": modes,
        "rounds": max(1, args.rounds),
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
    write_json(output_dir / "live_adversarial_results.json", payload)
    (output_dir / "phase11_live_adversarial.md").write_text(make_markdown(payload, output_dir), encoding="utf-8")
    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": payload["commit"],
        "status": status,
        "artifacts": [
            "live_adversarial_results.json",
            "phase11_live_adversarial.md",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase11-live-adversarial: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
