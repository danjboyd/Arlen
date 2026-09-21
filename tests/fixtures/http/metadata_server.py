"""Loopback wire-level metadata regression peer; no external network required."""
import json
import socketserver
import time
import ssl
import subprocess
import sys
import tempfile


TRACE = sys.argv[sys.argv.index("--trace") + 1] if "--trace" in sys.argv else None


def request_host(request):
    for line in request.split(b"\r\n")[1:]:
        if line.lower().startswith(b"host:"):
            return line.split(b":", 1)[1].strip()
    return b"127.0.0.1"


class Peer(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(2)
        try:
            request = self.request.recv(8192)
            while b"\r\n\r\n" not in request:
                chunk = self.request.recv(8192)
                if not chunk:
                    return
                request += chunk
            head, body = request.split(b"\r\n\r\n", 1)
            fields = dict(line.split(b":", 1) for line in head.split(b"\r\n")[1:] if b":" in line)
            length = next((int(v) for k, v in fields.items() if k.lower() == b"content-length"), 0)
            while len(body) < length:
                chunk = self.request.recv(8192)
                if not chunk:
                    return
                body += chunk
            path = request.split(b" ")[1]
            if TRACE:
                with open(TRACE, "ab") as trace:
                    trace.write(path + b"\n")
            if path == b"/disconnect":
                return
            if path == b"/timeout":
                time.sleep(1)
                return
            headers = b"HTTP/1.1 200 OK\r\nConnection: close\r\n"
            if path.startswith((b"/budget/", b"/absolute-budget/")):
                hops = int(path.rsplit(b"/", 1)[1])
                prefix = path.rsplit(b"/", 1)[0]
                target = prefix + b"/%d" % (hops - 1)
                if path.startswith(b"/absolute-budget/"):
                    target = b"http://" + request_host(request) + target
                payload = b"body-%d" % hops
                status = b"302 Budget Boundary" if hops else b"200 Finished"
                location = b"Location: " + target + b"\r\n" if hops else b""
                wire = (b"HTTP/1.1 " + status + b"\r\n" + location + b"X-Hop: %d\r\n" % hops
                        + b"Content-Length: %d\r\n\r\n" % len(payload) + payload)
            elif path == b"/reason-custom":
                wire = b"HTTP/1.1 503 Extractor Unavailable  \r\nContent-Length: 2\r\n\r\n{}"
            elif path == b"/reason-empty":
                wire = b"HTTP/1.1 200 \r\nContent-Length: 2\r\n\r\n{}"
            elif path == b"/reason-interim":
                wire = b"HTTP/1.1 100 Old Phrase\r\nX-Stale: yes\r\n\r\nHTTP/1.1 200 Final Phrase\r\nContent-Length: 2\r\n\r\n{}"
            elif path == b"/reason-redirect":
                wire = b"HTTP/1.1 302 Old Phrase\r\nLocation: /reason-empty\r\nContent-Length: 3\r\n\r\nold"
            elif path == b"/redirect-timeout":
                wire = b"HTTP/1.1 302 Found\r\nLocation: /timeout\r\nContent-Length: 0\r\n\r\n"
            elif path == b"/redirect-file":
                wire = b"HTTP/1.1 302 Found\r\nLocation: file:///etc/hosts\r\nContent-Length: 0\r\n\r\n"
            elif path.startswith(b"/method/"):
                code = int(path.rsplit(b"/", 1)[1])
                wire = b"HTTP/1.1 %d Redirect\r\nLocation: /echo\r\nContent-Length: 3\r\n\r\nold" % code
            elif path == b"/cross-origin":
                target = b"http://localhost:" + request_host(request).rsplit(b":", 1)[1] + b"/echo"
                wire = b"HTTP/1.1 302 Found\r\nLocation: " + target + b"\r\nContent-Length: 0\r\n\r\n"
            elif path == b"/echo":
                payload = json.dumps({"method": request.split(b" ")[0].decode(), "body": body.decode(),
                                      "headers": {k.decode().lower(): v.decode().strip() for k, v in fields.items()}}).encode()
                wire = headers + b"Content-Length: %d\r\n\r\n" % len(payload) + payload
            elif path == b"/redirect":
                wire = b"HTTP/1.1 302 Found\r\nLocation: /ok\r\nContent-Length: 0\r\n\r\n"
            elif path == b"/redirect-absolute":
                wire = (b"HTTP/1.1 302 Found\r\nLocation: http://" + request_host(request)
                        + b"/ok\r\nContent-Length: 0\r\n\r\n")
            elif path.startswith(b"/chain/"):
                hops = int(path.rsplit(b"/", 1)[1])
                target = b"/ok" if hops <= 1 else b"/chain/%d" % (hops - 1)
                wire = b"HTTP/1.1 302 Found\r\nLocation: " + target + b"\r\nContent-Length: 0\r\n\r\n"
            elif path == b"/loop":
                wire = b"HTTP/1.1 302 Found\r\nLocation: /loop\r\nContent-Length: 0\r\n\r\n"
            elif path == b"/status":
                wire = b"HTTP/1.1 503 Unavailable\r\nContent-Length: 2\r\n\r\n{}"
            elif path == b"/declared":
                wire = headers + b"Content-Length: 999999\r\n\r\n"
            elif path == b"/chunked":
                wire = headers + b"Transfer-Encoding: chunked\r\n\r\n20\r\n" + b"x" * 32 + b"\r\n1\r\nx\r\n0\r\n\r\n"
            elif path == b"/trickle":
                self.request.sendall(headers + b"Content-Length: 20\r\n\r\n")
                for _ in range(20):
                    self.request.sendall(b"x")
                    time.sleep(0.05)
                return
            elif path == b"/exact":
                wire = headers + b"Content-Length: 32\r\n\r\n" + b"x" * 32
            else:
                wire = headers + b"Content-Length: 2\r\n\r\n{}"
            self.request.sendall(wire)
        except (OSError, IndexError):
            pass


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True


with tempfile.TemporaryDirectory() as directory, Server(("127.0.0.1", 0), Peer) as server:
    if "--tls" in sys.argv:
        cert, key = directory + "/cert.pem", directory + "/key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-days", "1", "-subj", "/CN=localhost", "-keyout", key,
                        "-out", cert], check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print(server.server_address[1], flush=True)
    server.serve_forever()
