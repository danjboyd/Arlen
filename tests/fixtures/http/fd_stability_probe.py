import os
import socket

# Substituted by HTTPIntegrationTests; no third-party packages required.
PORT = __PORT__
SERVER_PID = __PID__
ROUNDS = 400

def descriptors():
    fd_dir = '/proc/%d/fd' % SERVER_PID
    total = 0
    dev_null = 0
    for entry in os.listdir(fd_dir):
        total += 1
        try:
            if os.readlink(os.path.join(fd_dir, entry)) == '/dev/null':
                dev_null += 1
        except OSError:
            pass
    return total, dev_null

def request(method, path, headers=b''):
    with socket.create_connection(('127.0.0.1', PORT), timeout=10) as sock:
        sock.sendall(method + b' ' + path + b' HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n' + headers + b'\r\n')
        data = b''
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
    head = data.split(b'\r\n\r\n', 1)[0]
    status = int(head.split(b' ')[1])
    etag = b''
    for line in head.split(b'\r\n')[1:]:
        name, _, value = line.partition(b':')
        if name.strip().lower() == b'etag':
            etag = value.strip()
    return status, etag

def round_trip():
    status, etag = request(b'GET', b'/media/voice-note')
    assert status == 200, status
    assert request(b'GET', b'/media/voice-note', b'Range: bytes=100-4095\r\n')[0] == 206
    assert request(b'GET', b'/media/voice-note', b'If-None-Match: ' + etag + b'\r\n')[0] == 304
    assert request(b'HEAD', b'/media/voice-note')[0] == 200
    assert request(b'GET', b'/static/photo.bin')[0] == 200

# Warm up so lazily opened runtime descriptors (logging, caches) are not counted.
for _ in range(20):
    round_trip()
before = descriptors()
for _ in range(ROUNDS):
    round_trip()
after = descriptors()
print('descriptors before=%s after=%s requests=%d' % (before, after, ROUNDS * 5))
assert after[1] <= before[1], ('/dev/null descriptors grew', before, after)
assert after[0] <= before[0] + 4, ('descriptors grew', before, after)
print('fd stability checks passed')
