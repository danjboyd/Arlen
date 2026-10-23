import concurrent.futures
import json
import os
import socket
import time

# Substituted by HTTPIntegrationTests. Real clock boundaries require a bounded
# wait; Expect synchronizes each test with the server's completed request head.
PORT = __PORT__
SPOOL = __SPOOL__
CHUNKED = __CHUNKED__
POLICY = __POLICY__
DELAY = 1.35


def response(sock):
    head = b''
    while not head.endswith(b'\r\n\r\n'):
        part = sock.recv(1)
        if not part:
            raise AssertionError(('incomplete response', head))
        head += part
    lines = head.split(b'\r\n')
    status = int(lines[0].split()[1])
    length = 0
    for line in lines[1:]:
        if line.lower().startswith(b'content-length:'):
            length = int(line.split(b':', 1)[1])
    body = b''
    while len(body) < length:
        part = sock.recv(length - len(body))
        if not part:
            raise AssertionError(('incomplete body', status, body, length))
        body += part
    return status, body


def head(chunked, length, keep_alive=False, expect=True):
    framing = (b'Transfer-Encoding: chunked\r\n' if chunked else
               b'Content-Length: %d\r\n' % length)
    return (b'GET /healthz HTTP/1.1\r\nHost: localhost\r\n' + framing
            + (b'Connection: keep-alive\r\n' if keep_alive else b'Connection: close\r\n')
            + (b'Expect: 100-continue\r\n' if expect else b'') + b'\r\n')


def split_body(chunked, payload, head_only=False):
    if not chunked:
        return (b'', payload) if head_only else (payload[:-1], payload[-1:])
    start = b'%x\r\n' % len(payload)
    end = b'\r\n0\r\n\r\n'
    return ((b'', start + payload + end) if head_only else
            (start + payload[:-1], payload[-1:] + end))


def delayed_case(chunked, length):
    payload = b'a' * length
    prefix, final = split_body(chunked, payload, head_only=(POLICY == 'deadline'))
    with socket.create_connection(('127.0.0.1', PORT), timeout=8) as sock:
        sock.sendall(head(chunked, length))
        assert response(sock)[0] == 100
        sock.sendall(prefix)
        time.sleep(DELAY)
        # Following request bytes must not inflate the preceding body's rate.
        tail = (b'GET /healthz HTTP/1.1\r\nHost: localhost\r\nX-Padding: '
                + b'x' * 2048 + b'\r\nConnection: close\r\n\r\n') if POLICY == 'rate' else b''
        sock.sendall(final + tail)
        status, body = response(sock)
        expected = 200 if POLICY == 'disabled' else 408
        result = {'policy': POLICY, 'chunked': chunked, 'length': length,
                  'status': status, 'expected': expected}
        print(json.dumps(result), flush=True)
        return status == expected and (status != 200 or body.strip() == b'ok')


def immediately_buffered_case(chunked, length):
    prefix, final = split_body(chunked, b'a' * length)
    with socket.create_connection(('127.0.0.1', PORT), timeout=8) as sock:
        sock.sendall(head(chunked, length, expect=False) + prefix + final)
        status, body = response(sock)
        assert status == 200 and body.strip() == b'ok', (status, body)


def fresh_pipeline_clocks():
    # Each request takes less than one second; the pair takes longer. A body
    # clock from the preceding keep-alive request must not survive into the next.
    with socket.create_connection(('127.0.0.1', PORT), timeout=8) as sock:
        for index in range(2):
            sock.sendall(head(False, 2, keep_alive=(index == 0)))
            assert response(sock)[0] == 100
            sock.sendall(b'a')
            time.sleep(0.65)
            sock.sendall(b'b')
            status, body = response(sock)
            assert status == 200 and body.strip() == b'ok', (index, status, body)


def healthy_rate_after_grace(chunked, upfront):
    payload = b'a' * 4096
    prefix = (b'%x\r\n' % len(payload) if chunked else b'') + payload[:upfront]
    final = payload[upfront:] + (b'\r\n0\r\n\r\n' if chunked else b'')
    with socket.create_connection(('127.0.0.1', PORT), timeout=8) as sock:
        sock.sendall(head(chunked, len(payload)))
        assert response(sock)[0] == 100
        sock.sendall(prefix)
        time.sleep(DELAY)
        sock.sendall(final)
        status, body = response(sock)
        assert status == 200 and body.strip() == b'ok', (chunked, upfront, status, body)
        print(json.dumps({'healthy_rate': True, 'chunked': chunked, 'upfront': upfront,
                          'status': status}), flush=True)


modes = [(False, 16), (False, 64)]
if CHUNKED:
    modes += [(True, 16), (True, 64)]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
    results = list(executor.map(lambda mode: delayed_case(*mode), modes))
for mode in modes:
    immediately_buffered_case(*mode)
if POLICY == 'deadline':
    fresh_pipeline_clocks()
elif POLICY == 'rate':
    healthy_modes = [(False, 1), (False, 4095)]
    if CHUNKED:
        healthy_modes += [(True, 1), (True, 4095)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        list(executor.map(lambda mode: healthy_rate_after_grace(*mode), healthy_modes))
until = time.monotonic() + 5
while any(name.startswith('arlen-body-') for name in os.listdir(SPOOL)):
    assert time.monotonic() < until, os.listdir(SPOOL)
    time.sleep(0.01)
assert all(results), 'late final body bypassed its active clock'
print('body clock checks passed', POLICY)
