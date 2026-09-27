import json
import os
import socket
import time

# Substituted by HTTPIntegrationTests; no third-party packages required.
PORT = __PORT__
SPOOL = __SPOOL__
THRESHOLD = 65536

def spool_entries():
    return sorted(n for n in os.listdir(SPOOL) if n.startswith('arlen-'))

def wait_until_empty(step):
    started = time.time()
    while spool_entries() and time.time() - started < 15:
        time.sleep(0.05)
    assert not spool_entries(), (step, round(time.time() - started, 2), spool_entries())

def multipart(payload, note=b'hello'):
    return (b'--Aa\r\nContent-Disposition: form-data; name="note"\r\n\r\n' + note +
            b'\r\n--Aa\r\nContent-Disposition: form-data; name="doc"; filename="a.bin"\r\n'
            b'Content-Type: application/octet-stream\r\n\r\n' + payload + b'\r\n--Aa--\r\n')

def head(body_length, keep_alive=False):
    return (b'POST /upload HTTP/1.1\r\nHost: localhost\r\n' +
            (b'' if keep_alive else b'Connection: close\r\n') +
            b'Content-Type: multipart/form-data; boundary=Aa\r\nContent-Length: ' +
            str(body_length).encode() + b'\r\n\r\n')

def read_response(sock, data=b''):
    while b'\r\n\r\n' not in data:
        chunk = sock.recv(65536)
        assert chunk, data
        data += chunk
    header, rest = data.split(b'\r\n\r\n', 1)
    status = int(header.split(b' ')[1])
    length = 0
    for line in header.split(b'\r\n')[1:]:
        name, _, value = line.partition(b':')
        if name.strip().lower() == b'content-length':
            length = int(value.strip())
    while len(rest) < length:
        chunk = sock.recv(65536)
        assert chunk, rest
        rest += chunk
    return status, rest[:length], rest[length:]

def post(body, keep_alive=False, sock=None, trickle=False):
    own = sock is None
    sock = sock or socket.create_connection(('127.0.0.1', PORT), timeout=10)
    try:
        payload = head(len(body), keep_alive) + body
        if trickle:
            for offset in range(0, len(payload), 32768):
                sock.sendall(payload[offset:offset + 32768])
                time.sleep(0.002)
        else:
            sock.sendall(payload)
        status, response, extra = read_response(sock)
        assert not extra, extra
        return status, response
    finally:
        if own:
            sock.close()

payload = bytes((i * 7) % 251 for i in range(3 * 1024 * 1024))
body = multipart(payload)

# A body above the threshold streams to a spool file; the large part is spooled too.
status, response = post(body, trickle=True)
assert status == 200, (status, response)
seen = json.loads(response)
assert seen['bodyLength'] == len(body), seen
assert seen['bodyFiles'] == 1 and seen['uploadDirectories'] == 1, seen
assert seen['uploads'] == [{'size': len(payload), 'sum': sum(payload) & 0xffffffff, 'spooled': True}], seen
assert seen['field'] == 'hello', seen
wait_until_empty('large upload')

# Small bodies stay in memory.
small = multipart(b'tiny')
status, response = post(small)
seen = json.loads(response)
assert status == 200 and seen['bodyFiles'] == 0 and seen['uploads'][0]['spooled'] == 0, seen

# Keep-alive: a spooled request followed by a small one on the same connection.
# Reads stop at Content-Length, so the second request is not swallowed.
with socket.create_connection(('127.0.0.1', PORT), timeout=10) as sock:
    sock.sendall(head(len(body), keep_alive=True) + body + head(len(small), keep_alive=True) + small)
    status, response, extra = read_response(sock)
    assert status == 200 and json.loads(response)['uploads'][0]['size'] == len(payload), response
    status, response, extra = read_response(sock, extra)
    assert status == 200 and json.loads(response)['uploads'][0]['spooled'] == 0, response
wait_until_empty('keep-alive')

# Client disconnects mid-body: the partial spool file is removed and the server keeps serving.
for _ in range(4):
    with socket.create_connection(('127.0.0.1', PORT), timeout=10) as sock:
        sock.sendall(head(len(body)) + body[:THRESHOLD * 4])
wait_until_empty('client aborts')
status, _ = post(small)
assert status == 200

# The total body limit is still enforced before anything is spooled.
with socket.create_connection(('127.0.0.1', PORT), timeout=10) as sock:
    sock.sendall(head(8 * 1024 * 1024 + 1))
    status, _, _ = read_response(sock)
    assert status == 413, status
assert not spool_entries(), spool_entries()
print('multipart spool checks passed')
