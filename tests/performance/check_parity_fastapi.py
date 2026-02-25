#!/usr/bin/env python3
import argparse
import http.client
import json
import os
import socket
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass
class RunningServer:
    name: str
    process: subprocess.Popen
    log_handle: object
    log_path: str
    host: str
    port: int


def utc_now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def http_request(host: str, port: int, path: str, timeout: float = 2.0, headers=None) -> dict:
    conn = http.client.HTTPConnection(host, port, timeout=timeout)
    req_headers = headers or {}
    try:
        conn.request("GET", path, headers=req_headers)
        response = conn.getresponse()
        body = response.read()
        out_headers = {k.lower(): v for (k, v) in response.getheaders()}
        return {
            "status": response.status,
            "headers": out_headers,
            "body": body,
        }
    finally:
        conn.close()


def wait_ready(name: str, host: str, port: int, path: str, timeout_seconds: float = 8.0) -> None:
    start = time.time()
    last_error = ""
    while (time.time() - start) < timeout_seconds:
        try:
            response = http_request(host, port, path, timeout=0.5)
            if response["status"] == 200:
                return
            last_error = f"status={response['status']}"
        except Exception as exc:
            last_error = str(exc)
        time.sleep(0.05)
    raise RuntimeError(f"{name} did not become ready on {path}: {last_error}")


def start_server(name: str, cmd: list, host: str, port: int, env: dict, log_dir: Path, cwd: Path) -> RunningServer:
    log_path = log_dir / f"{name}.log"
    log_handle = open(log_path, "w", encoding="utf-8")
    process = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return RunningServer(
        name=name,
        process=process,
        log_handle=log_handle,
        log_path=str(log_path),
        host=host,
        port=port,
    )


def stop_server(server: RunningServer) -> None:
    if server is None:
        return
    if server.process.poll() is None:
        server.process.terminate()
        try:
            server.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.process.kill()
            server.process.wait(timeout=5)
    try:
        server.log_handle.close()
    except Exception:
        pass


def parse_http_response_from_socket(sock: socket.socket) -> dict:
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("connection closed before response headers")
        data += chunk

    header_blob, body = data.split(b"\r\n\r\n", 1)
    header_lines = header_blob.decode("utf-8", "replace").split("\r\n")
    if not header_lines:
        raise RuntimeError("missing status line")
    status_line = header_lines[0]
    parts = status_line.split(" ", 2)
    if len(parts) < 2:
        raise RuntimeError(f"invalid status line: {status_line}")
    status = int(parts[1])

    headers = {}
    for line in header_lines[1:]:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        headers[key.strip().lower()] = value.strip()

    content_length = int(headers.get("content-length", "0"))
    while len(body) < content_length:
        chunk = sock.recv(4096)
        if not chunk:
            break
        body += chunk

    return {
        "status": status,
        "headers": headers,
        "body": body[:content_length] if content_length > 0 else b"",
    }


def check_core_scenarios(arlen_base: tuple, fastapi_base: tuple) -> dict:
    checks = {}

    arlen_healthz = http_request(arlen_base[0], arlen_base[1], "/healthz")
    fastapi_healthz = http_request(fastapi_base[0], fastapi_base[1], "/healthz")
    checks["C01_healthz"] = {
        "pass": (
            arlen_healthz["status"] == 200
            and fastapi_healthz["status"] == 200
            and arlen_healthz["body"] == b"ok\n"
            and fastapi_healthz["body"] == b"ok\n"
        ),
        "arlen_status": arlen_healthz["status"],
        "fastapi_status": fastapi_healthz["status"],
        "arlen_body": arlen_healthz["body"].decode("utf-8", "replace"),
        "fastapi_body": fastapi_healthz["body"].decode("utf-8", "replace"),
    }

    arlen_status = http_request(arlen_base[0], arlen_base[1], "/api/status")
    fastapi_status = http_request(fastapi_base[0], fastapi_base[1], "/api/status")
    arlen_status_json = json.loads(arlen_status["body"].decode("utf-8", "replace"))
    fastapi_status_json = json.loads(fastapi_status["body"].decode("utf-8", "replace"))
    checks["C02_api_status"] = {
        "pass": (
            arlen_status["status"] == 200
            and fastapi_status["status"] == 200
            and arlen_status_json.get("ok") is True
            and fastapi_status_json.get("ok") is True
            and isinstance(arlen_status_json.get("timestamp"), (int, float))
            and isinstance(fastapi_status_json.get("timestamp"), (int, float))
            and isinstance(arlen_status_json.get("server"), str)
            and isinstance(fastapi_status_json.get("server"), str)
        ),
        "arlen_status": arlen_status["status"],
        "fastapi_status": fastapi_status["status"],
        "arlen_payload": arlen_status_json,
        "fastapi_payload": fastapi_status_json,
    }

    arlen_echo = http_request(arlen_base[0], arlen_base[1], "/api/echo/hank")
    fastapi_echo = http_request(fastapi_base[0], fastapi_base[1], "/api/echo/hank")
    arlen_echo_json = json.loads(arlen_echo["body"].decode("utf-8", "replace"))
    fastapi_echo_json = json.loads(fastapi_echo["body"].decode("utf-8", "replace"))
    expected_echo = {"name": "hank", "path": "/api/echo/hank"}
    checks["C03_api_echo"] = {
        "pass": (
            arlen_echo["status"] == 200
            and fastapi_echo["status"] == 200
            and arlen_echo_json == expected_echo
            and fastapi_echo_json == expected_echo
        ),
        "arlen_status": arlen_echo["status"],
        "fastapi_status": fastapi_echo["status"],
        "arlen_payload": arlen_echo_json,
        "fastapi_payload": fastapi_echo_json,
    }

    return checks


def keepalive_probe(host: str, port: int) -> dict:
    sock = socket.create_connection((host, port), timeout=3)
    try:
        first_request = (
            f"GET /healthz HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            f"User-Agent: phaseb-parity-check\r\n"
            f"\r\n"
        ).encode("utf-8")
        sock.sendall(first_request)
        first_response = parse_http_response_from_socket(sock)

        second_request = (
            f"GET /api/status HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            f"Connection: close\r\n"
            f"User-Agent: phaseb-parity-check\r\n"
            f"\r\n"
        ).encode("utf-8")
        sock.sendall(second_request)
        second_response = parse_http_response_from_socket(sock)

        first_connection = first_response["headers"].get("connection", "").lower()
        keepalive_ok = "close" not in first_connection

        return {
            "pass": (
                first_response["status"] == 200
                and second_response["status"] == 200
                and keepalive_ok
            ),
            "first_status": first_response["status"],
            "second_status": second_response["status"],
            "first_connection_header": first_response["headers"].get("connection", ""),
        }
    finally:
        try:
            sock.close()
        except Exception:
            pass


def check_keepalive(arlen_base: tuple, fastapi_base: tuple) -> dict:
    arlen_result = keepalive_probe(arlen_base[0], arlen_base[1])
    fastapi_result = keepalive_probe(fastapi_base[0], fastapi_base[1])
    return {
        "pass": arlen_result["pass"] and fastapi_result["pass"],
        "arlen": arlen_result,
        "fastapi": fastapi_result,
    }


def check_arlen_backpressure(arlen_bin: str, repo_root: Path, log_dir: Path) -> dict:
    host = "127.0.0.1"
    port = find_free_port()
    env = os.environ.copy()
    env["ARLEN_MAX_HTTP_SESSIONS"] = "1"

    server = start_server(
        name="arlen_backpressure",
        cmd=[arlen_bin, "--port", str(port)],
        host=host,
        port=port,
        env=env,
        log_dir=log_dir,
        cwd=repo_root,
    )
    try:
        wait_ready("arlen_backpressure", host, port, "/healthz")

        partial = socket.create_connection((host, port), timeout=3)
        partial.sendall((f"GET /healthz HTTP/1.1\r\nHost: {host}:{port}\r\n").encode("utf-8"))
        time.sleep(0.2)

        second = socket.create_connection((host, port), timeout=3)
        second.sendall(
            (
                f"GET /healthz HTTP/1.1\r\n"
                f"Host: {host}:{port}\r\n"
                f"Connection: close\r\n\r\n"
            ).encode("utf-8")
        )
        second_response = parse_http_response_from_socket(second)
        second.close()
        partial.close()
        time.sleep(0.2)

        recovery = http_request(host, port, "/healthz")
        reason = second_response["headers"].get("x-arlen-backpressure-reason", "")
        return {
            "pass": (
                second_response["status"] == 503
                and reason == "http_session_limit"
                and recovery["status"] == 200
                and recovery["body"] == b"ok\n"
            ),
            "status": second_response["status"],
            "reason": reason,
            "recovery_status": recovery["status"],
            "log_path": server.log_path,
        }
    finally:
        stop_server(server)


def check_fastapi_backpressure(python_bin: str, app_dir: str, repo_root: Path, log_dir: Path) -> dict:
    host = "127.0.0.1"
    port = find_free_port()
    env = os.environ.copy()
    cmd = [
        python_bin,
        "-m",
        "uvicorn",
        "app:app",
        "--app-dir",
        app_dir,
        "--host",
        host,
        "--port",
        str(port),
        "--workers",
        "1",
        "--limit-concurrency",
        "2",
        "--log-level",
        "warning",
    ]

    server = start_server(
        name="fastapi_backpressure",
        cmd=cmd,
        host=host,
        port=port,
        env=env,
        log_dir=log_dir,
        cwd=repo_root,
    )
    try:
        wait_ready("fastapi_backpressure", host, port, "/healthz")

        hold_socket_one = socket.create_connection((host, port), timeout=3)
        hold_socket_two = socket.create_connection((host, port), timeout=3)

        hold_socket_one.sendall(
            (
                f"GET /hold?seconds=1.5 HTTP/1.1\r\n"
                f"Host: {host}:{port}\r\n"
                f"Connection: close\r\n"
                f"User-Agent: phaseb-parity-check\r\n\r\n"
            ).encode("utf-8")
        )
        hold_socket_two.sendall(
            (
                f"GET /hold?seconds=1.5 HTTP/1.1\r\n"
                f"Host: {host}:{port}\r\n"
                f"Connection: close\r\n"
                f"User-Agent: phaseb-parity-check\r\n\r\n"
            ).encode("utf-8")
        )

        saw_503 = False
        statuses = []
        deadline = time.time() + 1.2
        while time.time() < deadline:
            try:
                probe = http_request(host, port, "/healthz", timeout=0.4)
                statuses.append(probe["status"])
                if probe["status"] == 503:
                    saw_503 = True
                    break
            except Exception:
                statuses.append("error")
            time.sleep(0.1)

        hold_response_one = parse_http_response_from_socket(hold_socket_one)
        hold_response_two = parse_http_response_from_socket(hold_socket_two)
        hold_socket_one.close()
        hold_socket_two.close()

        recovery = http_request(host, port, "/healthz", timeout=1.0)

        hold_statuses = [hold_response_one["status"], hold_response_two["status"]]
        observed_overload = saw_503 or any(status == 503 for status in hold_statuses)

        return {
            "pass": (
                observed_overload
                and recovery["status"] == 200
                and recovery["body"] == b"ok\n"
            ),
            "saw_503": saw_503,
            "probe_statuses": statuses,
            "hold_statuses": hold_statuses,
            "observed_overload": observed_overload,
            "recovery_status": recovery["status"],
            "log_path": server.log_path,
        }
    finally:
        stop_server(server)


def main() -> int:
    parser = argparse.ArgumentParser(description="Phase B Arlen/FastAPI parity checker")
    parser.add_argument("--repo-root", default=None, help="Arlen repository root")
    parser.add_argument("--arlen-bin", default="./build/boomhauer", help="Path to Arlen boomhauer binary")
    parser.add_argument(
        "--fastapi-app-dir",
        default="tests/performance/fastapi_reference",
        help="Directory containing FastAPI app.py",
    )
    parser.add_argument("--python-bin", default=sys.executable, help="Python interpreter for uvicorn")
    parser.add_argument(
        "--output",
        default="build/perf/parity_fastapi_latest.json",
        help="Path to write parity report JSON",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root) if args.repo_root else Path(__file__).resolve().parents[2]
    arlen_bin = str((repo_root / args.arlen_bin).resolve()) if not os.path.isabs(args.arlen_bin) else args.arlen_bin
    fastapi_app_dir = (
        str((repo_root / args.fastapi_app_dir).resolve())
        if not os.path.isabs(args.fastapi_app_dir)
        else args.fastapi_app_dir
    )
    output_path = Path(args.output)
    if not output_path.is_absolute():
        output_path = (repo_root / output_path).resolve()

    log_dir = (repo_root / "build" / "perf" / "parity_logs").resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    report = {
        "timestamp_utc": utc_now_iso(),
        "phase": "B",
        "passed": False,
        "checks": {},
        "environment": {
            "repo_root": str(repo_root),
            "arlen_bin": arlen_bin,
            "fastapi_app_dir": fastapi_app_dir,
            "python_bin": args.python_bin,
        },
        "logs": {},
    }

    arlen_host = "127.0.0.1"
    fastapi_host = "127.0.0.1"
    arlen_port = find_free_port()
    fastapi_port = find_free_port()

    arlen_server = None
    fastapi_server = None

    try:
        arlen_server = start_server(
            name="arlen_core",
            cmd=[arlen_bin, "--port", str(arlen_port)],
            host=arlen_host,
            port=arlen_port,
            env=os.environ.copy(),
            log_dir=log_dir,
            cwd=repo_root,
        )
        fastapi_server = start_server(
            name="fastapi_core",
            cmd=[
                args.python_bin,
                "-m",
                "uvicorn",
                "app:app",
                "--app-dir",
                fastapi_app_dir,
                "--host",
                fastapi_host,
                "--port",
                str(fastapi_port),
                "--workers",
                "1",
                "--log-level",
                "warning",
            ],
            host=fastapi_host,
            port=fastapi_port,
            env=os.environ.copy(),
            log_dir=log_dir,
            cwd=repo_root,
        )

        wait_ready("arlen_core", arlen_host, arlen_port, "/healthz")
        wait_ready("fastapi_core", fastapi_host, fastapi_port, "/healthz")

        report["checks"].update(
            check_core_scenarios(
                (arlen_host, arlen_port),
                (fastapi_host, fastapi_port),
            )
        )
        report["checks"]["C04_keepalive"] = check_keepalive(
            (arlen_host, arlen_port),
            (fastapi_host, fastapi_port),
        )
    finally:
        stop_server(arlen_server)
        stop_server(fastapi_server)

    report["checks"]["C05_backpressure"] = {
        "arlen": check_arlen_backpressure(arlen_bin, repo_root, log_dir),
        "fastapi": check_fastapi_backpressure(args.python_bin, fastapi_app_dir, repo_root, log_dir),
    }
    report["checks"]["C05_backpressure"]["pass"] = (
        report["checks"]["C05_backpressure"]["arlen"]["pass"]
        and report["checks"]["C05_backpressure"]["fastapi"]["pass"]
    )

    for key in ["C01_healthz", "C02_api_status", "C03_api_echo", "C04_keepalive", "C05_backpressure"]:
        if key not in report["checks"]:
            raise RuntimeError(f"missing check: {key}")
    report["passed"] = all(report["checks"][key]["pass"] for key in report["checks"])

    for name in [
        "arlen_core.log",
        "fastapi_core.log",
        "arlen_backpressure.log",
        "fastapi_backpressure.log",
    ]:
        path = (log_dir / name)
        if path.exists():
            report["logs"][name] = str(path)

    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write("\n")

    print(f"phaseb parity: wrote report {output_path}")
    if report["passed"]:
        print("phaseb parity: PASS")
        return 0
    print("phaseb parity: FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
