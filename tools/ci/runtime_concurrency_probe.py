#!/usr/bin/env python3
import argparse
import base64
import os
import random
import socket
import struct
import subprocess
import threading
import time
import urllib.request
from typing import Dict, List, Tuple


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

    server = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_ready(port)
        for _ in range(iterations):
            run_mixed_probe_once(port, expect_keep_alive)
    finally:
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
