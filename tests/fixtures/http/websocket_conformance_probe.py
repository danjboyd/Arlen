# GitHub issues 239 and 214: websocket idle handling and RFC 6455 conformance.
# Runs against the framework dev server (`build/boomhauer`) started with
# ARLEN_WEBSOCKET_PING_INTERVAL_SECONDS=1 and ARLEN_CONNECTION_TIMEOUT_SECONDS=2.
import base64, os, socket, struct, threading, time

PORT = __PORT__


def connect(path):
    sock = socket.create_connection(("127.0.0.1", PORT), timeout=10)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall((f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{PORT}\r\nUpgrade: websocket\r\n"
                  f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    head = b""
    while b"\r\n\r\n" not in head:
        chunk = sock.recv(1)
        if not chunk:
            raise RuntimeError("closed during handshake")
        head += chunk
    assert b" 101 " in head.split(b"\r\n", 1)[0], head
    return sock


def frame(opcode, payload=b"", fin=True, rsv=0, length=None):
    mask = os.urandom(4)
    first = (0x80 if fin else 0) | (rsv << 4) | opcode
    n = len(payload) if length is None else length
    if n <= 125:
        header = bytes([first, 0x80 | n])
    elif n <= 65535:
        header = bytes([first, 0x80 | 126]) + struct.pack("!H", n)
    else:
        header = bytes([first, 0x80 | 127]) + struct.pack("!Q", n)
    return header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload))


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise EOFError("closed")
        data += chunk
    return data


def recv_frame(sock):
    b0, b1 = recv_exact(sock, 2)
    n = b1 & 0x7F
    if n == 126:
        n = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif n == 127:
        n = struct.unpack("!Q", recv_exact(sock, 8))[0]
    return b0 & 0x0F, recv_exact(sock, n)


def expect_close(sock, code, label):
    sock.settimeout(10)
    while True:
        opcode, payload = recv_frame(sock)
        if opcode == 0x9:
            continue
        assert opcode == 0x8, (label, opcode, payload)
        got = struct.unpack("!H", payload[:2])[0] if len(payload) >= 2 else None
        assert got == code, (label, got)
        return


# 214: protocol violations close with the RFC 6455 code.
cases = [
    ("oversized ping", frame(0x9, b"x" * 126), 1002),
    ("fragmented ping", frame(0x9, b"x", fin=False), 1002),
    ("RSV1 without an extension", frame(0x1, b"hi", rsv=4), 1002),
    ("reserved opcode", frame(0x3, b"hi"), 1002),
    ("invalid UTF-8 text", frame(0x1, b"\xc3\x28"), 1007),
    ("continuation without a message", frame(0x0, b"hi"), 1002),
    ("new message inside a fragmented one", frame(0x1, b"a", fin=False) + frame(0x1, b"b"), 1002),
]
for label, data, code in cases:
    sock = connect("/ws/echo")
    sock.sendall(data)
    expect_close(sock, code, label)
    sock.close()

sock = connect("/ws/echo")
sock.sendall(frame(0x1, b"", length=2 * 1024 * 1024)[:14])  # header claims 2 MiB
expect_close(sock, 1009, "message too big")
sock.close()

# 214: fragmented messages are reassembled; the peer's close code is echoed.
sock = connect("/ws/echo")
sock.sendall(frame(0x1, b"hel", fin=False) + frame(0x9, b"mid") + frame(0x0, b"lo"))
seen = []
while len(seen) < 2:
    seen.append(recv_frame(sock))
assert (0xA, b"mid") in seen and (0x1, b"hello") in seen, seen
sock.sendall(frame(0x8, struct.pack("!H", 1000) + b"bye"))
expect_close(sock, 1000, "close echo")
sock.close()

# 239: a quiet subscriber that answers pings outlives connectionTimeoutSeconds
# (2 s) and still gets messages.
subscriber = connect("/ws/channel/idle239")
subscriber.settimeout(10)
pings = 0
deadline = time.time() + 5
while time.time() < deadline:
    subscriber.settimeout(max(0.1, deadline - time.time()))
    try:
        opcode, payload = recv_frame(subscriber)
    except socket.timeout:
        break
    assert opcode == 0x9, opcode
    pings += 1
    subscriber.sendall(frame(0xA, payload))
assert pings >= 2, pings
publisher = connect("/ws/channel/idle239")
publisher.sendall(frame(0x1, b"still here"))
subscriber.settimeout(5)
while True:
    opcode, payload = recv_frame(subscriber)
    if opcode == 0x9:
        subscriber.sendall(frame(0xA, payload))
        continue
    assert (opcode, payload) == (0x1, b"still here"), (opcode, payload)
    break
publisher.close()
subscriber.close()

# 239: a client that never answers is pinged, then closed with 1001.
silent = connect("/ws/channel/silent239")
started = time.time()
expect_close(silent, 1001, "missed pong")
assert time.time() - started < 6, time.time() - started
silent.close()
print("websocket checks passed")
