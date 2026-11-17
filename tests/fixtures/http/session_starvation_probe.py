# Long-lived websocket and SSE sessions must not hold HTTP workers.
# Each session ran inline on the worker that accepted it, so with the default
# 8 workers, 8 open streams left no worker for anything else and /healthz
# hung until a stream closed. Sessions now run on their own threads.
#
# The probe opens SESSIONS sessions (twice the worker count) and checks:
#   1. every session is accepted (101 / 200 event-stream);
#   2. a fresh /healthz is answered within 3 s while they stay open;
#   3. every session still works (websocket echo / SSE event delivery);
#   4. with LIMIT > 0, session LIMIT+1 gets 503 and the limit's backpressure
#      reason, and once the sessions close, a new session is accepted again
#      (the reservations were released);
#   5. with PID > 0, SIGTERM ends the server while sessions are open: every
#      session socket closes within 5 s (the test then checks the exit status).
import base64, os, signal, socket, struct, time

PORT = __PORT__
MODE = "__MODE__"          # "ws" or "sse"
SESSIONS = __SESSIONS__
LIMIT = __LIMIT__
PID = __PID__
STREAM = f"starve{int(time.time() * 1000)}"


def read_head(sock):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    head, _, rest = data.partition(b"\r\n\r\n")
    return head.decode("utf-8", "replace"), rest


def open_session():
    sock = socket.create_connection(("127.0.0.1", PORT), timeout=5)
    if MODE == "ws":
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        sock.sendall((f"GET /ws/echo HTTP/1.1\r\nHost: 127.0.0.1:{PORT}\r\n"
                      "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                      f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    else:
        sock.sendall(f"GET /sse?stream={STREAM} HTTP/1.1\r\nHost: 127.0.0.1:{PORT}\r\n\r\n".encode())
    head, rest = read_head(sock)
    return sock, head, rest


def accepted(head):
    status = head.split("\r\n", 1)[0]
    if MODE == "ws":
        return " 101 " in status
    return " 200 " in status and "text/event-stream" in head.lower()


def http_get(path):
    start = time.time()
    sock = socket.create_connection(("127.0.0.1", PORT), timeout=10)
    sock.sendall(f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{PORT}\r\nConnection: close\r\n\r\n".encode())
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    sock.close()
    return data.decode("utf-8", "replace"), time.time() - start


def ws_send_text(sock, text):
    payload = text.encode()
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    sock.sendall(bytes([0x81, 0x80 | len(payload)]) + mask + masked)


def recv_exact(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise RuntimeError("websocket closed mid-frame")
        data += chunk
    return data


def ws_read_text(sock):
    first = recv_exact(sock, 2)
    length = first[1] & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(sock, 2))[0]
    return recv_exact(sock, length).decode()


def wait_for_sse_event(sock, rest):
    data = rest
    deadline = time.time() + 5
    sock.settimeout(0.5)
    while b"data:" not in data and time.time() < deadline:
        try:
            chunk = sock.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            break
        data += chunk
    sock.settimeout(5)
    return b"data:" in data


def close_session(sock):
    try:
        if MODE == "ws":
            sock.sendall(bytes([0x88, 0x82]) + b"\0\0\0\0" + struct.pack("!H", 1000))
    except OSError:
        pass
    sock.close()


# 1. Open twice as many sessions as workers.
sessions = []
for idx in range(SESSIONS):
    try:
        sock, head, rest = open_session()
    except socket.timeout:
        raise RuntimeError(f"session {idx + 1} of {SESSIONS} got no response in 5 s: "
                           "open sessions are holding every HTTP worker")
    if not accepted(head):
        raise RuntimeError(f"session {idx + 1} not accepted: {head}")
    sessions.append((sock, rest))

# 2. A fresh request is still served promptly.
response, elapsed = http_get("/healthz")
if " 200 " not in response.split("\r\n", 1)[0] or elapsed > 3.0:
    raise RuntimeError(f"/healthz with {SESSIONS} open {MODE} sessions: {elapsed:.1f}s {response[:200]}")

# 3. Every session still works.
if MODE == "ws":
    for idx, (sock, _) in enumerate(sessions):
        ws_send_text(sock, f"hello {idx}")
        echoed = ws_read_text(sock)
        if echoed != f"hello {idx}":
            raise RuntimeError(f"session {idx} echoed {echoed!r}")
else:
    appended, _ = http_get(f"/append?stream={STREAM}&n=1")
    if " 200 " not in appended.split("\r\n", 1)[0]:
        raise RuntimeError(f"append failed: {appended[:200]}")
    for idx, (sock, rest) in enumerate(sessions):
        if not wait_for_sse_event(sock, rest):
            raise RuntimeError(f"SSE session {idx} got no event within 5 s")

# 4. The session limit holds, and closing sessions frees it.
if LIMIT > 0:
    reason = "websocket_session_limit" if MODE == "ws" else "sse_session_limit"
    extra, head, _ = open_session()
    extra.close()
    if " 503 " not in head.split("\r\n", 1)[0] or f"X-Arlen-Backpressure-Reason: {reason}" not in head:
        raise RuntimeError(f"session {LIMIT + 1} should hit the limit: {head}")
    for sock, _ in sessions:
        close_session(sock)
    sessions = []
    deadline = time.time() + 5
    while True:
        sock, head, rest = open_session()
        if accepted(head):
            sessions.append((sock, rest))
            break
        sock.close()
        if time.time() > deadline:
            raise RuntimeError(f"limit not released after closing sessions: {head}")
        time.sleep(0.2)

# 5. Shutdown with open sessions.
if PID > 0:
    while len(sessions) < 4:
        sock, head, rest = open_session()
        if not accepted(head):
            raise RuntimeError(f"session for shutdown check not accepted: {head}")
        sessions.append((sock, rest))
    os.kill(PID, signal.SIGTERM)
    deadline = time.time() + 5
    for sock, _ in sessions:
        sock.settimeout(max(0.1, deadline - time.time()))
        try:
            while sock.recv(65536):
                pass
        except socket.timeout:
            raise RuntimeError("a session stayed open 5 s after SIGTERM")
        except OSError:
            pass
        sock.close()
    sessions = []

for sock, _ in sessions:
    close_session(sock)
print(f"session starvation checks passed: {MODE} sessions={SESSIONS} healthz={elapsed:.3f}s")
