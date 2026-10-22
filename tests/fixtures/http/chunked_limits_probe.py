import json
import os
import socket
import time

PORT = __PORT__
SPOOL = __SPOOL__
CHUNKED = __CHUNKED__


def connect():
    return socket.create_connection(('127.0.0.1', PORT), timeout=10)


def head(path):
    return (b'POST ' + path + b' HTTP/1.1\r\nHost: localhost\r\n'
            b'Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n')


def response(sock):
    data = b''
    while True:
        part = sock.recv(65536)
        if not part:
            break
        data += part
    headers, _, body = data.partition(b'\r\n\r\n')
    return int(headers.split(b' ')[1]), body


def fnv(data):
    value = 2166136261
    for byte in data:
        value = ((value ^ byte) * 16777619) & 0xffffffff
    return value


def frame(data):
    return b'%x\r\n' % len(data) + data + b'\r\n'


def entries():
    return [name for name in os.listdir(SPOOL) if name.startswith('arlen-body-')]


def await_entries(present):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if bool(entries()) == present:
            return
        time.sleep(0.01)
    raise AssertionError(('spool presence', present, entries()))


if CHUNKED:
    # Actual socket-path reproduction of repeated whole-buffer parsing. The
    # raised upload limit admits this encoded body; one million tiny chunks
    # must complete within the probe's ordinary 10-second socket timeout.
    started = time.monotonic()
    with connect() as sock:
        sock.sendall(head(b'/upload') + b'1\r\na\r\n' * (1024 * 1024) + b'0\r\n\r\n')
        status, body = response(sock)
        assert status == 200 and json.loads(body)['bodyLength'] == 1024 * 1024, (status, body)
    print("dense chunked socket seconds %.3f" % (time.monotonic() - started), flush=True)
    await_entries(False)

    # Hold an unknown-length upload open above the 1 MiB threshold. A spool
    # file must exist before completion, rather than buffering then dumping.
    payload = bytes(range(256)) * 8192
    with connect() as sock:
        sock.sendall(head(b'/upload') + frame(payload))
        await_entries(True)
        sock.sendall(b'0\r\n\r\n')
        status, body = response(sock)
        assert status == 200 and json.loads(body)['bodyLength'] == len(payload), (status, body)
        assert json.loads(body)['bodyFnv'] == fnv(payload), body
    await_entries(False)

    # A large upload route must not raise the small/default route's limit.
    with connect() as sock:
        sock.sendall(head(b'/small') + frame(b'a' * 65537) + b'0\r\n\r\n')
        assert response(sock)[0] == 413
    with connect() as sock:
        sock.sendall(head(b'/small') + frame(b'a\x00b') + b'0\r\n\r\n')
        status, body = response(sock)
        assert status == 200 and json.loads(body)['bodyLength'] == 3, (status, body)

    # Fragment across chunk-size, extension, CRLF, payload, terminal and trailer
    # boundaries, then ensure the next pipelined request remains intact.
    with connect() as sock:
        wire = (head(b'/small').replace(b'Connection: close', b'Connection: keep-alive')
                + b'3;foo=bar\r\na\x00b\r\n0\r\nX-Test-Trailer: ignored\r\n\r\n'
                + b'GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n')
        for index in range(0, len(wire), 7):
            sock.sendall(wire[index:index + 7])
        status, body = response(sock)
        assert status == 200 and b'"bodyLength":3' in body.replace(b' ', b''), (status, body)
        assert body.count(b'HTTP/1.1 200') == 1, body

    # The delivered request owns its spool even if its handler throws.
    with connect() as sock:
        sock.sendall(head(b'/explode') + frame(payload) + b'0\r\n\r\n')
        assert response(sock)[0] == 500
    await_entries(False)

    # A malformed terminator and an aborted upload release an existing spool.
    with connect() as sock:
        sock.sendall(head(b'/upload') + frame(payload))
        await_entries(True)
        sock.sendall(b'z\r\n')
        assert response(sock)[0] == 400
    await_entries(False)
    with connect() as sock:
        sock.sendall(head(b'/upload') + frame(payload))
        await_entries(True)
    await_entries(False)
else:
    # Legacy builds retain their explicit rejection of transfer coding.
    with connect() as sock:
        sock.sendall(head(b'/small') + frame(b'a') + b'0\r\n\r\n')
        assert response(sock)[0] == 400

print('chunked limit checks passed')
