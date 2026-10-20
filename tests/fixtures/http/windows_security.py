"""Wire regressions against the caller's running boomhauer (PORT in globals)."""
import base64
import ctypes
import http.client
import os
from pathlib import Path
import socket
import subprocess
import tempfile


def handshake(origin=None):
    peer = socket.create_connection(('127.0.0.1', PORT), timeout=3)
    key = base64.b64encode(os.urandom(16)).decode()
    headers = [f'GET /ws/channel/security-test HTTP/1.1', f'Host: 127.0.0.1:{PORT}',
               'Connection: Upgrade', 'Upgrade: websocket', 'Sec-WebSocket-Version: 13',
               f'Sec-WebSocket-Key: {key}']
    if origin is not None:
        headers.append(f'Origin: {origin}')
    peer.sendall(('\r\n'.join(headers) + '\r\n\r\n').encode())
    response = b''
    while b'\r\n\r\n' not in response:
        chunk = peer.recv(4096)
        assert chunk, response
        response += chunk
    return peer, int(response.split()[1])


peer, status = handshake('https://attacker.invalid')
assert status == 403, status
peer.close()
peer, status = handshake(f'http://127.0.0.1:{PORT}')
assert status == 101, status
peer.close()
first, status = handshake()
assert status == 101
second, status = handshake()
assert status == 101
payload = b'forged-live-operation'
mask = b'abcd'
first.sendall(bytes([0x81, 0x80 | len(payload)]) + mask +
              bytes(value ^ mask[index % 4] for index, value in enumerate(payload)))
for peer in (first, second):
    peer.settimeout(0.3)
    try:
        data = peer.recv(1)
    except socket.timeout:
        pass
    else:
        raise AssertionError(('channel rebroadcast', data))
    peer.close()

if os.name == 'nt':
    def status_for(path):
        connection = http.client.HTTPConnection('127.0.0.1', PORT, timeout=3)
        connection.request('GET', path)
        response = connection.getresponse()
        status = response.status
        response.read()
        connection.close()
        return status

    root = Path.cwd().resolve()
    public = root / 'public'
    with tempfile.TemporaryDirectory(prefix='security-', dir=public) as temp:
        directory = Path(temp)
        assert directory.resolve().parent == public.resolve()
        prefix = '/static/' + directory.name
        (directory / 'ok.js').write_text('safe')
        (directory / 'token.cssx').write_text('private')
        (directory / 'secret.env').write_text('private')
        (directory / '.secret.js').write_text('hidden-private')
        (directory / 'secret.env:stream.js').write_text('stream-private')
        assert status_for(prefix + '/ok.js') == 200
        assert status_for(prefix + '/secret.env:stream.js') == 404
        assert status_for(prefix + '/CON.js') == 404
        assert status_for(prefix + '/NUL.css') == 404
        assert status_for(prefix + '/token.cssx') == 404
        buffer = ctypes.create_unicode_buffer(32768)
        count = ctypes.windll.kernel32.GetShortPathNameW(str(directory / 'token.cssx'), buffer, len(buffer))
        assert count > 0
        # Where NTFS short names are enabled, test the actual alias.
        short = buffer.value.replace('\\', '/').rsplit('/', 1)[-1]
        assert status_for(prefix + '/' + short) == 404
        print('short-name-alias-tested' if short.lower() != 'token.cssx' else 'short-names-disabled-on-volume')
        count = ctypes.windll.kernel32.GetShortPathNameW(str(directory / '.secret.js'), buffer, len(buffer))
        assert count > 0
        hidden_short = buffer.value.replace('\\', '/').rsplit('/', 1)[-1]
        assert status_for(prefix + '/' + hidden_short) == 404
        with tempfile.TemporaryDirectory(prefix='outside-', dir=root / 'build') as outside:
            assert Path(outside).resolve().parent == (root / 'build').resolve()
            (Path(outside) / 'leak.js').write_text('outside-private')
            junction = directory / 'junction'
            subprocess.run(['cmd.exe', '/d', '/c', 'mklink', '/J', str(junction).replace('/', '\\'), str(outside).replace('/', '\\')],
                           check=True)
            try:
                assert status_for(prefix + '/junction/leak.js') == 404
            finally:
                os.rmdir(junction)
    # Windows exclusive binding must reject a second local listener.
    duplicate = socket.socket()
    try:
        duplicate.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            duplicate.bind(('127.0.0.1', PORT))
        except OSError:
            pass
        else:
            raise AssertionError('second bind succeeded')
    finally:
        duplicate.close()
print('security-wire-passed')
