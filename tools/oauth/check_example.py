#!/usr/bin/env python3
"""Loopback HTTP smoke: OAuth discovery/challenges; no tenant or token issuance."""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def main():
    config = json.loads((ROOT / "examples/mcp_app/entra.example.json").read_text()
                        .replace("<TENANT_GUID>", "11111111-1111-1111-1111-111111111111")
                        .replace("<RESEARCH_API_APPLICATION_GUID>", "22222222-2222-2222-2222-222222222222")
                        .replace("<PUBLIC_MCP_HOST>", "mcp.example.test")
                        .replace("<DELEGATED_SCOPE>", "Fixture.Read"))
    # A valid legacy token and configured legacy verifier must not bypass OAuth.
    secret = "ignored-fixture-secret-01234567890123456789"
    config["auth"] = {"enabled": True, "bearerSecret": secret, "issuer": "old-pilot", "audience": "old-research"}
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=")
    signing = encode({"alg": "HS256"}) + b"." + encode({"sub": "old-user", "iss": "old-pilot", "aud": "old-research", "exp": int(time.time()) + 300, "scope": "Fixture.Read"})
    legacy = (signing + b"." + base64.urlsafe_b64encode(hmac.new(secret.encode(), signing, hashlib.sha256).digest()).rstrip(b"=")).decode()
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="arlen-oauth-") as directory:
        path = Path(directory) / "config.json"
        path.write_text(json.dumps(config))
        env = dict(os.environ, MCP_EXAMPLE_OAUTH_CONFIG=str(path),
                   MCP_EXAMPLE_SECRET=secret)
        process = subprocess.Popen([str(ROOT / "build/mcp-example"), str(port)],
                                   cwd=ROOT, env=env, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        def request(path, bearer=None):
            headers = {"Host": "spoofed.example", "X-Forwarded-Host": "spoofed.example",
                       "Forwarded": "host=spoofed.example;proto=http"}
            if bearer:
                headers["Authorization"] = "Bearer " + bearer
            req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", headers=headers)
            try:
                return urllib.request.urlopen(req, timeout=2)
            except urllib.error.HTTPError as error:
                return error
        try:
            for _ in range(100):
                if process.poll() is not None:
                    raise AssertionError("OAuth example exited before becoming ready")
                try:
                    with request("/.well-known/oauth-protected-resource/research/mcp") as response:
                        assert response.status == 200
                        metadata = json.load(response)
                        assert metadata["resource"] == "https://mcp.example.test/research/mcp"
                    break
                except urllib.error.URLError:
                    time.sleep(0.05)
            else:
                raise AssertionError("OAuth example did not start")
            for route in ("/research/mcp", "/catalog/1"):
                for bearer in (None, legacy):
                    with request(route, bearer) as response:
                        assert response.status == 401
                        challenge = response.headers["WWW-Authenticate"]
                        assert 'resource_metadata="https://mcp.example.test/.well-known/oauth-protected-resource/research/mcp"' in challenge
                        assert "spoofed" not in challenge
                        assert "no-store" in response.headers["Cache-Control"]
            print("OAuth example HTTP discovery/challenge checks passed (no live Entra).")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
