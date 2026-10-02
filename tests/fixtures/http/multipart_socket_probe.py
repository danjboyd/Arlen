import socket
import time

# Substituted by HTTPIntegrationTests; no third-party packages required.
PORT = __PORT__

def request(body, expected, fragmented=False, length=None):
    head = (b'GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n'
            b'Content-Type: multipart/form-data; boundary="Aa"\r\nContent-Length: '
            + str(len(body) if length is None else length).encode() + b'\r\n\r\n')
    with socket.create_connection(('127.0.0.1', PORT), timeout=5) as sock:
        payload = head + body
        if fragmented:
            for offset in range(0, len(payload), 3):
                sock.sendall(payload[offset:offset+3])
                time.sleep(0.001)
        else:
            sock.sendall(payload)
        response = b''
        while b'\r\n' not in response:
            chunk = sock.recv(4096)
            assert chunk, response
            response += chunk
        assert int(response.split(b' ')[1]) == expected, response

field = b'--Aa\r\nContent-Disposition: form-data; name="x"\r\n\r\n'
file = b'--Aa\r\nContent-Disposition: form-data; name="doc"; filename="../a.bin"\r\n\r\n'
valid = field + b'\r\n' + file + b'\x00\xff\x80\r\n--AaX\r\n--Aa--X\r\n--Aa--\r\n'
request(valid, 200, fragmented=True)
request(valid[:-7], 400, fragmented=True)
request(field + b'x'*65537 + b'\r\n--Aa--', 413)
request(file + b'x'*1048577 + b'\r\n--Aa--', 413)
request((field+b'x\r\n')*129+b'--Aa--', 413)
request(b'--Aa\r\nX-Header: '+b'x'*16384+b'\r\n\r\nx\r\n--Aa--', 413)
# 110 MiB configured request cap is checked at headers, before allocation/read.
request(b'', 413, length=110*1024*1024+1)
# Repeated mid-body disconnects leave the server usable; no spool files exist.
for _ in range(8):
    with socket.create_connection(('127.0.0.1', PORT), timeout=5) as sock:
        sock.sendall(b'POST /healthz HTTP/1.1\r\nHost: localhost\r\n'
                     b'Content-Type: multipart/form-data; boundary=Aa\r\n'
                     b'Content-Length: 100000\r\n\r\n'+file+b'aborted')
request(valid, 200, fragmented=True)
print('multipart socket checks passed')
