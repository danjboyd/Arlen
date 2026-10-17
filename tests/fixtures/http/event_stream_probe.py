# GitHub issue 240: SSE event streams under concurrent appends.
# Each client starts after the latest sequence while three appenders run; it
# must see every later event exactly once, in order, with `id:` = sequence. A
# Last-Event-ID reconnect must resume right after that sequence.
import json, re, socket, threading, time, urllib.request

PORT = __PORT__
STREAM = f"gap{int(time.time() * 1000)}"
stop = threading.Event()


def get(path):
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}{path}", timeout=10) as res:
        return res.read().decode()


def appender():
    while not stop.is_set():
        get(f"/append?stream={STREAM}&n=10")


def read_sse(path, headers="", seconds=1.5):
    sock = socket.create_connection(("127.0.0.1", PORT), timeout=10)
    sock.settimeout(0.5)
    sock.sendall(f"GET {path} HTTP/1.1\r\nHost: x\r\n{headers}\r\n".encode())
    data = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            chunk = sock.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            break
        data += chunk
    sock.close()
    events = []
    for frame in data.split(b"\n\n"):
        ident = re.search(rb"^id: ?(\d+)$", frame, re.M)
        payload = re.search(rb"^data: ?(.*)$", frame, re.M)
        if ident and payload:
            events.append((int(ident.group(1)), json.loads(payload.group(1))["sequence"]))
    return events


def client(results, idx):
    after = int(re.search(r"last=(\d+)", get(f"/append?stream={STREAM}&n=1")).group(1))
    results[idx] = (after, read_sse(f"/sse?stream={STREAM}&after={after}"))


get(f"/append?stream={STREAM}&n=5")
threads = [threading.Thread(target=appender, daemon=True) for _ in range(3)]
for t in threads:
    t.start()
time.sleep(0.2)
results = {}
clients = [threading.Thread(target=client, args=(results, idx)) for idx in range(12)]
for t in clients:
    t.start()
    time.sleep(0.03)
for t in clients:
    t.join()
stop.set()
for t in threads:
    t.join()

problems = []
for idx, (after, events) in sorted(results.items()):
    sequences = [seq for _, seq in events]
    if not sequences:
        problems.append(f"client {idx}: after={after} received nothing")
        continue
    if any(ident != seq for ident, seq in events):
        problems.append(f"client {idx}: an SSE id differs from the event sequence")
    expected = list(range(after + 1, sequences[-1] + 1))
    if sequences != expected:
        missing = sorted(set(expected) - set(sequences))
        problems.append(f"client {idx}: after={after} got {len(sequences)} {sequences[0]}..{sequences[-1]} "
                        f"missing={len(missing)} dup={len(sequences) - len(set(sequences))} "
                        f"ordered={sequences == sorted(sequences)}")
assert not problems, "\n".join(problems)

# Last-Event-ID resumes after that sequence when the request names no cursor.
latest = int(re.search(r"last=(\d+)", get(f"/append?stream={STREAM}&n=3")).group(1))
resumed = [seq for _, seq in read_sse(f"/sse?stream={STREAM}", f"Last-Event-ID: {latest - 2}\r\n", 0.8)]
assert resumed[:2] == [latest - 1, latest], (latest, resumed)

# A client that stops reading must not stall appenders: live events queue per
# session (bounded) and the session's own thread does the socket sends.
stalled = socket.create_connection(("127.0.0.1", PORT), timeout=10)
stalled.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
stalled.sendall(f"GET /sse?stream={STREAM}&after={latest} HTTP/1.1\r\nHost: x\r\n\r\n".encode())
time.sleep(0.3)
started = time.time()
for _ in range(30):
    get(f"/append?stream={STREAM}&n=100")
elapsed = time.time() - started
stalled.close()
assert elapsed < 20, f"3000 appends took {elapsed:.1f}s with a stalled subscriber"
print("event stream checks passed")
