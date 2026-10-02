#!/usr/bin/env python3
"""Real HTTP example smoke test; --sdk additionally uses the official Python MCP client."""
import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def token(secret, **claims):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=")
    body = encode({"alg": "HS256", "typ": "JWT"}) + b"." + encode({
        "sub": "example-reader", "iss": "mcp-example", "aud": "arlen-catalog",
        "scope": "catalog:read", "exp": int(time.time()) + 300, **claims,
    })
    return (body + b"." + base64.urlsafe_b64encode(hmac.new(secret.encode(), body, hashlib.sha256).digest()).rstrip(b"=")).decode()


async def sdk_check(url, credential):
    import httpx
    from mcp import ClientSession
    from mcp.client.streamable_http import streamable_http_client
    async with httpx.AsyncClient(headers={"Authorization": "Bearer " + credential}) as http:
        async with streamable_http_client(url, http_client=http) as (read, write, _):
            async with ClientSession(read, write) as session:
                initialized = await session.initialize()
                assert initialized.protocolVersion == "2025-11-25"
                listed = await session.list_tools()
                assert [t.name for t in listed.tools] == ["catalog.item.v1", "catalog.summary.v1"]
                item = await session.call_tool("catalog.item.v1", {"id": "1"})
                assert not item.isError and item.structuredContent["title"] == "GNUstep Handbook"
                summary = await session.call_tool("catalog.summary.v1", {})
                assert not summary.isError and summary.structuredContent == {"count": 2}
                assert any(c.type == "resource_link" for c in summary.content)
                missing = await session.call_tool("catalog.item.v1", {"id": "999"})
                assert missing.isError
    print("Official MCP Python SDK initialization/list/call/output-schema/error checks passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    secret = secrets.token_hex(32)
    url = f"http://127.0.0.1:{port}/mcp"
    credential = token(secret)
    with tempfile.TemporaryFile() as log:
        process = subprocess.Popen([str(root / "build/mcp-example"), str(port)], cwd=root,
                                   env={**os.environ, "MCP_EXAMPLE_SECRET": secret}, stdout=log, stderr=log)
        try:
            for _ in range(100):
                if process.poll() is not None:
                    log.seek(0)
                    raise RuntimeError(log.read().decode())
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=.1):
                        break
                except OSError:
                    time.sleep(.05)
            else:
                raise RuntimeError("Example did not listen within five seconds")

            def send(method, params=None, headers=None, notification=False):
                payload = {"jsonrpc": "2.0", "method": method, "params": params or {}}
                if not notification:
                    payload["id"] = 1
                req = urllib.request.Request(url, json.dumps(payload).encode(), headers={
                    "Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                    "MCP-Protocol-Version": "2025-11-25", "Authorization": "Bearer " + credential,
                    **(headers or {}),
                })
                try:
                    response = urllib.request.urlopen(req, timeout=5)
                except urllib.error.HTTPError as error:
                    response = error
                data = response.read()
                return response.status, json.loads(data) if data else None, response.headers

            status, initialized, headers = send("initialize", {
                "protocolVersion": "2025-11-25", "capabilities": {},
                "clientInfo": {"name": "arlen-http-smoke", "version": "1"},
            }, {"MCP-Protocol-Version": ""})
            assert status == 200 and initialized["result"]["capabilities"] == {"tools": {}}, initialized
            assert headers.get("Mcp-Session-Id") is None
            assert send("notifications/initialized", notification=True)[:2] == (202, None)
            assert send("tools/list")[1]["result"]["tools"][0]["name"] == "catalog.item.v1"
            result = send("tools/call", {"name": "catalog.item.v1", "arguments": {"id": "1"}})[1]
            assert result["result"]["structuredContent"]["title"] == "GNUstep Handbook", result
            assert send("tools/call", {"name": "catalog.summary.v1"})[1]["result"]["structuredContent"] == {"count": 2}
            assert send("tools/list", headers={"Authorization": ""})[0] == 401
            for invalid in (token(secret, aud="downstream-service"), token(secret, exp=1), token("wrong-secret")):
                assert send("tools/list", headers={"Authorization": "Bearer " + invalid})[0] == 401
            assert send("tools/list", headers={"Authorization": "Bearer " + token(secret, scope="other")})[0] == 403
            assert send("tools/list", headers={"Origin": "https://evil.example"})[0] == 403
            assert send("tools/list", headers={"MCP-Protocol-Version": "2026-07-28"})[0] == 400
            print("Real HTTP protocol, JWT audience/expiry/signature/scope and Origin checks passed")
            if args.sdk:
                asyncio.run(sdk_check(url, credential))
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
