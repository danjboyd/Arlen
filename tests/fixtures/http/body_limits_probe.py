import ctypes
import json
import os
import socket
import struct
import threading
import time

# Substituted by HTTPIntegrationTests; no third-party packages required.
PORT = __PORT__
SPOOL = __SPOOL__
SERVER_PID = __PID__
MIB = 1024 * 1024

def spool_entries():
    return sorted(n for n in os.listdir(SPOOL) if n.startswith('arlen-'))

def wait_until_empty(step, limit=15):
    # Aborted connections can still be mid-read when the client has already
    # closed, so the spool directory may be empty for a moment before a file
    # appears. Require it to stay empty for a full second.
    started = time.time()
    quiet_since = None
    while time.time() - started < limit:
        if spool_entries():
            quiet_since = None
        elif quiet_since is None:
            quiet_since = time.time()
        elif time.time() - quiet_since >= 1.0:
            return
        time.sleep(0.05)
    raise AssertionError((step, round(time.time() - started, 2), spool_entries()))

def rss_anon_kib():
    # Linux: anonymous resident memory. Without /proc (macOS), the physical
    # footprint, which likewise leaves out clean file-backed pages. Bodies and
    # uploads are memory-mapped from their spool files, so total RSS would
    # count them even though nothing is buffered on the heap.
    status_path = '/proc/%d/status' % SERVER_PID
    if os.path.exists(status_path):
        with open(status_path) as status:
            for line in status:
                if line.startswith('RssAnon:'):
                    return int(line.split()[1])
        return 0
    return phys_footprint_kib()

def phys_footprint_kib():
    # proc_pid_rusage(RUSAGE_INFO_V2): a 16-byte UUID, then uint64 fields;
    # ri_phys_footprint is the eighth.
    libsystem = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    info = ctypes.create_string_buffer(512)
    if libsystem.proc_pid_rusage(SERVER_PID, 2, info) != 0:
        raise OSError('proc_pid_rusage failed for %d' % SERVER_PID)
    return struct.unpack_from('=Q', info.raw, 16 + 7 * 8)[0] // 1024

def head(path, length, content_type=b'multipart/form-data; boundary=Aa'):
    return (b'POST ' + path + b' HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n'
            b'Content-Type: ' + content_type + b'\r\nContent-Length: ' + str(length).encode() + b'\r\n\r\n')

def read_status(sock):
    data = b''
    while b'\r\n' not in data:
        chunk = sock.recv(65536)
        if not chunk:
            break
        data += chunk
    return int(data.split(b' ')[1]) if data else 0

def read_response(sock):
    data = b''
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        data += chunk
    header, _, body = data.partition(b'\r\n\r\n')
    return int(header.split(b' ')[1]), body

def multipart(payload):
    return (b'--Aa\r\nContent-Disposition: form-data; name="doc"; filename="w9.pdf"\r\n'
            b'Content-Type: application/pdf\r\n\r\n' + payload + b'\r\n--Aa--\r\n')

def fnv(data):
    h = 2166136261
    for b in data:
        h = ((h ^ b) * 16777619) & 0xffffffff
    return h

def post(path, body, chunk=1024 * 1024, content_type=b'multipart/form-data; boundary=Aa'):
    with socket.create_connection(('127.0.0.1', PORT), timeout=30) as sock:
        payload = head(path, len(body), content_type) + body
        for offset in range(0, len(payload), chunk):
            sock.sendall(payload[offset:offset + chunk])
        return read_response(sock)

# Tricky bytes: NUL, invalid UTF-8, CR/LF and near-miss boundary runs (a real
# delimiter may not appear in content), repeated to 20 MiB.
pattern = bytes(range(256)) + b'\xff\xfe\xc3\x28\r\n--AaX\r\n--Aa--X--Aa\r\n\x00\x00'
payload = (pattern * (20 * MIB // len(pattern) + 1))[:20 * MIB]
body = multipart(payload)
expected_fnv = fnv(payload)

# /small keeps the 64 KiB default: refused at the head, before any body is sent.
with socket.create_connection(('127.0.0.1', PORT), timeout=10) as sock:
    sock.sendall(head(b'/small', 1 * MIB))
    assert read_status(sock) == 413
# /upload accepts 20 MiB, spooled, byte-exact.
status, response = post(b'/upload', body)
assert status == 200, (status, response[:200])
seen = json.loads(response)['uploads']
assert seen == [{'size': len(payload), 'fnv': expected_fnv, 'spooled': 1}], seen
wait_until_empty('upload')
# /upload refuses 30 MiB at the head.
with socket.create_connection(('127.0.0.1', PORT), timeout=10) as sock:
    sock.sendall(head(b'/upload', 30 * MIB))
    assert read_status(sock) == 413
# Small bodies on the small route still work.
status, response = post(b'/small', b'a=1', 16, b'application/x-www-form-urlencoded')
assert status == 200 and json.loads(response)['bodyLength'] == 3, response

# Handler exception after spooling: files removed.
status, _ = post(b'/explode', body)
assert status == 500, status
wait_until_empty('handler exception')
# Client abort mid-body.
for _ in range(3):
    with socket.create_connection(('127.0.0.1', PORT), timeout=10) as sock:
        sock.sendall(head(b'/upload', len(body)) + body[:5 * MIB])
wait_until_empty('client abort')
# Read timeout mid-body (server connectionTimeoutSeconds is 2).
stalled = socket.create_connection(('127.0.0.1', PORT), timeout=30)
stalled.sendall(head(b'/upload', len(body)) + body[:3 * MIB])
time.sleep(4)
wait_until_empty('read timeout')
stalled.close()

# Eight concurrent 20 MiB uploads: anonymous memory stays near the baseline,
# because bodies and parts live in spool files, not the heap.
baseline = rss_anon_kib()
peak = [baseline]
done = threading.Event()
def sample():
    while not done.is_set():
        peak[0] = max(peak[0], rss_anon_kib())
        time.sleep(0.01)
results = []
def upload():
    results.append(post(b'/upload', body))
sampler = threading.Thread(target=sample)
sampler.start()
workers = [threading.Thread(target=upload) for _ in range(8)]
[w.start() for w in workers]
[w.join() for w in workers]
done.set()
sampler.join()
assert all(s == 200 for s, _ in results), [s for s, _ in results]
growth_mib = (peak[0] - baseline) / 1024.0
print('rss_anon growth MiB %.1f' % growth_mib)
# Spool threshold (1 MiB) x 8 plus buffers and fixed overhead; buffering would be >= 160 MiB.
assert growth_mib < 64, growth_mib
wait_until_empty('concurrent uploads')
print('body limit checks passed')
