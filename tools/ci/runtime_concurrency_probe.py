#!/usr/bin/env python3
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
from typing import Dict, List, Optional, Tuple


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
        raise RuntimeError(response.decode("utf-8", "replace"))
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
        raise RuntimeError(f"unexpected opcode {opcode}")
    return payload.decode("utf-8")


def run_channel_probe(port: int, expect_keep_alive: bool) -> None:
    if expect_keep_alive:
        publisher = ws_connect(port, "/ws/channel/runtime-gate")
        subscriber = ws_connect(port, "/ws/channel/runtime-gate")
        try:
            ws_send_text(publisher, "runtime-fanout")
            first = ws_recv_text(publisher)
            second = ws_recv_text(subscriber)
            if first != "runtime-fanout" or second != "runtime-fanout":
                raise RuntimeError("websocket channel fanout mismatch")
        finally:
            publisher.close()
            subscriber.close()
        return

    client = ws_connect(port, "/ws/channel/runtime-gate")
    try:
        ws_send_text(client, "runtime-fanout")
        echoed = ws_recv_text(client)
        if echoed != "runtime-fanout":
            raise RuntimeError("websocket channel self-echo mismatch")
    finally:
        client.close()


def run_sse_probe(port: int) -> None:
    with urllib.request.urlopen(
        f"http://127.0.0.1:{port}/sse/ticker?count=3", timeout=5
    ) as response:
        body = response.read().decode("utf-8")
        content_type = response.headers.get("Content-Type", "")
    if "text/event-stream" not in content_type:
        raise RuntimeError(f"unexpected sse content type: {content_type}")
    if body.count("event: tick") < 3:
        raise RuntimeError("missing expected sse events")


def read_json_payload(data: bytes) -> Dict[str, object]:
    decoded = data.decode("utf-8", "replace")
    parsed = json.loads(decoded)
    if not isinstance(parsed, dict):
        raise RuntimeError("expected JSON object payload")
    return parsed


def run_route_surface_probe(port: int) -> None:
    root = urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=4).read().decode(
        "utf-8", "replace"
    )
    if "Arlen EOC Dev Server" not in root:
        raise RuntimeError("root render payload missing expected marker")

    about = urllib.request.urlopen(f"http://127.0.0.1:{port}/about", timeout=4).read().decode(
        "utf-8", "replace"
    )
    if "Arlen Phase 1 server" not in about:
        raise RuntimeError("about route payload mismatch")

    status_payload = read_json_payload(
        urllib.request.urlopen(f"http://127.0.0.1:{port}/api/status", timeout=4).read()
    )
    if status_payload.get("ok") is not True:
        raise RuntimeError("api/status did not report ok=true")

    echo_payload = read_json_payload(
        urllib.request.urlopen(f"http://127.0.0.1:{port}/api/echo/runtime-probe", timeout=4).read()
    )
    if echo_payload.get("name") != "runtime-probe":
        raise RuntimeError("api/echo route payload mismatch")


def run_data_layer_probe(port: int) -> None:
    invalid_write = urllib.request.Request(
        f"http://127.0.0.1:{port}/api/db/items",
        data=b"{}",
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(invalid_write, timeout=5) as response:
            payload = read_json_payload(response.read())
            status = response.status
    except urllib.error.HTTPError as exc:
        payload = read_json_payload(exc.read())
        status = exc.code

    if status != 400:
        raise RuntimeError(f"db write validation expected 400, got {status}")
    if payload.get("error", {}).get("code") != "bad_request":  # type: ignore[union-attr]
        raise RuntimeError("db write validation payload missing bad_request")

    read_url = f"http://127.0.0.1:{port}/api/db/items?category=phase9h&limit=2"
    try:
        with urllib.request.urlopen(read_url, timeout=5) as response:
            read_payload = read_json_payload(response.read())
            read_status = response.status
    except urllib.error.HTTPError as exc:
        read_payload = read_json_payload(exc.read())
        read_status = exc.code

    if read_status == 200:
        if "items" not in read_payload:
            raise RuntimeError("db read success payload missing items")
        return
    if read_status != 500:
        raise RuntimeError(f"db read expected 200/500, got {read_status}")
    error_code = read_payload.get("error", {}).get("code")  # type: ignore[union-attr]
    if error_code not in {"db_error", "db_unavailable"}:
        raise RuntimeError(f"unexpected db read error code: {error_code}")


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


def run_mixed_probe_once(port: int, expect_keep_alive: bool) -> None:
    ws = ws_connect(port, "/ws/echo")
    try:
        for idx in range(4):
            token = f"ws-{idx}"
            ws_send_text(ws, token)
            echoed = ws_recv_text(ws)
            if echoed != token:
                raise RuntimeError("websocket echo mismatch")
    finally:
        ws.close()

    run_channel_probe(port, expect_keep_alive)
    run_sse_probe(port)

    if expect_keep_alive:
        sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        sock.settimeout(5)
        try:
            for idx in range(4):
                connection = "close" if idx == 3 else "keep-alive"
                request = (
                    f"GET /healthz HTTP/1.1\r\n"
                    f"Host: 127.0.0.1:{port}\r\n"
                    f"Connection: {connection}\r\n\r\n"
                ).encode("utf-8")
                sock.sendall(request)
                status, headers, body = read_http_response(sock)
                if "200" not in status or body != b"ok\n":
                    raise RuntimeError(f"bad keep-alive status: {status}")
                if headers.get("connection", "").lower() != connection:
                    raise RuntimeError("keep-alive connection header mismatch")
        finally:
            sock.close()
    else:
        for _ in range(4):
            sock = socket.create_connection(("127.0.0.1", port), timeout=5)
            sock.settimeout(5)
            try:
                request = (
                    f"GET /healthz HTTP/1.1\r\n"
                    f"Host: 127.0.0.1:{port}\r\n"
                    "Connection: keep-alive\r\n\r\n"
                ).encode("utf-8")
                sock.sendall(request)
                status, headers, body = read_http_response(sock)
                if "200" not in status or body != b"ok\n":
                    raise RuntimeError(f"bad serialized status: {status}")
                if headers.get("connection", "").lower() != "close":
                    raise RuntimeError("serialized connection header mismatch")
                sock.settimeout(0.5)
                try:
                    tail = sock.recv(1)
                except OSError:
                    tail = b""
                if tail not in (b"",):
                    raise RuntimeError("serialized socket expected closed")
            finally:
                sock.close()

    errors: List[str] = []

    def worker(idx: int) -> None:
        try:
            slow = urllib.request.urlopen(
                f"http://127.0.0.1:{port}/api/sleep?ms=140", timeout=5
            ).read().decode("utf-8")
            if "sleep_ms" not in slow:
                errors.append(f"slow-{idx}")
            fast = urllib.request.urlopen(
                f"http://127.0.0.1:{port}/healthz", timeout=4
            ).read().decode("utf-8")
            if fast != "ok\n":
                errors.append(f"fast-{idx}")
        except Exception as exc:  # noqa: BLE001
            errors.append(str(exc))

    threads: List[threading.Thread] = []
    for idx in range(6):
        t = threading.Thread(target=worker, args=(idx,))
        t.start()
        threads.append(t)
    for thread in threads:
        thread.join()

    if errors:
        raise RuntimeError("; ".join(errors))

    final = urllib.request.urlopen(
        f"http://127.0.0.1:{port}/healthz", timeout=4
    ).read().decode("utf-8")
    if final != "ok\n":
        raise RuntimeError(f"final health check failed: {final!r}")


def run_mode(binary: str, mode: str, expect_keep_alive: bool, iterations: int) -> None:
    port = random.randint(32000, 34000)
    command = [binary, "--port", str(port)]
    if mode == "serialized":
        command = [binary, "--env", "production", "--port", str(port)]

    overlap_stop: Optional[threading.Event] = None
    load_thread: Optional[threading.Thread] = None
    server = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        wait_ready(port)
        run_route_surface_probe(port)
        run_data_layer_probe(port)
        for _ in range(iterations):
            run_mixed_probe_once(port, expect_keep_alive)

        overlap_errors: List[str] = []
        overlap_stop = threading.Event()

        def overlap_load() -> None:
            while not overlap_stop.is_set():
                try:
                    body = urllib.request.urlopen(
                        f"http://127.0.0.1:{port}/healthz", timeout=1.0
                    ).read().decode("utf-8")
                    if body != "ok\n":
                        overlap_errors.append(f"bad health body: {body!r}")
                    urllib.request.urlopen(
                        f"http://127.0.0.1:{port}/api/sleep?ms=40", timeout=1.5
                    ).read()
                except Exception as exc:  # noqa: BLE001
                    message = str(exc).lower()
                    transient = any(
                        token in message
                        for token in (
                            "connection refused",
                            "connection reset",
                            "remote end closed",
                            "timed out",
                            "bad status line",
                        )
                    )
                    if not transient and not overlap_stop.is_set():
                        overlap_errors.append(str(exc))
                time.sleep(0.02)

        load_thread = threading.Thread(target=overlap_load)
        load_thread.start()
        time.sleep(0.25)

        server.terminate()
        try:
            server.wait(timeout=8)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=5)

        server = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        wait_ready(port)
        run_route_surface_probe(port)
        run_data_layer_probe(port)

        overlap_stop.set()
        load_thread.join(timeout=5)
        if overlap_errors:
            raise RuntimeError("; ".join(overlap_errors))

        run_mixed_probe_once(port, expect_keep_alive)
    finally:
        if overlap_stop is not None:
            overlap_stop.set()
        if load_thread is not None:
            load_thread.join(timeout=5)
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=8)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run runtime concurrency probe")
    parser.add_argument("--binary", required=True, help="Path to boomhauer binary")
    parser.add_argument(
        "--iterations",
        type=int,
        default=2,
        help="Probe iterations per mode",
    )
    args = parser.parse_args()

    if args.iterations < 1:
        raise ValueError("--iterations must be >= 1")

    run_mode(args.binary, "concurrent", True, args.iterations)
    run_mode(args.binary, "serialized", False, args.iterations)
    print("runtime-concurrency-probe: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
