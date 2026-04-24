#!/usr/bin/env python3
"""Small deterministic HTTP sites for Phase 37 acceptance probes."""

from __future__ import annotations

import argparse
import html
import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


def json_bytes(payload: dict[str, object]) -> bytes:
    return json.dumps(payload, sort_keys=True, indent=2).encode("utf-8")


class Phase37Handler(BaseHTTPRequestHandler):
    server_version = "Phase37Acceptance/1.0"

    def log_message(self, fmt: str, *args: object) -> None:
        self.server.log.write((fmt % args) + "\n")  # type: ignore[attr-defined]
        self.server.log.flush()  # type: ignore[attr-defined]

    @property
    def site(self) -> str:
        return self.server.site  # type: ignore[attr-defined]

    def write(self, status: int, body: bytes, content_type: str = "text/html", headers: dict[str, str] | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Phase37-Site", self.site)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def write_json(self, status: int, payload: dict[str, object]) -> None:
        self.write(status, json_bytes(payload), "application/json")

    def read_body(self) -> str:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return ""
        return self.rfile.read(length).decode("utf-8", errors="replace")

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/healthz":
            self.write_json(200, {"status": "ok", "site": self.site})
            return
        if self.site == "eoc_kitchen_sink":
            self.handle_eoc_get(path)
        elif self.site == "mvc_crud":
            self.handle_mvc_get(path)
        elif self.site == "module_portal":
            self.handle_module_get(path)
        elif self.site == "data_orm_reference":
            self.handle_data_get(path)
        else:
            self.write_json(404, {"error": "unknown_site"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if self.site == "mvc_crud":
            self.handle_mvc_post(path)
        elif self.site == "data_orm_reference":
            self.handle_data_post(path)
        else:
            self.write_json(405, {"error": "method_not_allowed"})

    def handle_eoc_get(self, path: str) -> None:
        if path == "/eoc":
            title = html.escape("A&B <C>", quote=True)
            body = "\n".join([
                "<html><body>",
                "<main>",
                f"<h1>{title}</h1>",
                "<div class=\"trusted\"><strong>trusted raw</strong></div>",
                "<p class=\"nil\"></p>",
                "<p class=\"keypath\">dev@example.test</p>",
                "<ul><li>admin</li><li>billing</li></ul>",
                "</main>",
                "<aside><li>profile</li></aside>",
                "</body></html>",
            ]).encode("utf-8")
            self.write(200, body)
            return
        if path == "/eoc/strict-error":
            self.write_json(500, {
                "code": "ALNEOCErrorTemplateExecutionFailed",
                "column": 1,
                "line": 1,
                "local": "title",
                "path": "golden/requires_title.html.eoc",
            })
            return
        self.write_json(404, {"error": "not_found"})

    def handle_mvc_get(self, path: str) -> None:
        if path == "/items":
            self.write(200, b"<h1>Items</h1><form method=\"post\"><input name=\"title\"></form>")
            return
        if path == "/items/42":
            self.write_json(200, {"id": 42, "title": "Existing item"})
            return
        if path == "/assets/app.css":
            self.write(200, b"body { color: #111; }\n", "text/css")
            return
        self.write_json(404, {"error": "not_found"})

    def handle_mvc_post(self, path: str) -> None:
        body = self.read_body()
        fields = parse_qs(body)
        if path == "/items":
            title = fields.get("title", [""])[0]
            if not title:
                self.write_json(422, {"error": "validation_failed", "field": "title"})
                return
            self.write(303, b"", headers={"Location": "/items/1", "Set-Cookie": "phase37_session=ok; Path=/; HttpOnly"})
            return
        if path == "/csrf":
            token = fields.get("csrf", [""])[0]
            if token != "known-token":
                self.write_json(403, {"error": "csrf_rejected"})
                return
            self.write_json(200, {"status": "csrf_ok"})
            return
        self.write_json(404, {"error": "not_found"})

    def handle_module_get(self, path: str) -> None:
        pages = {
            "/auth/login": "<h1>Auth Login</h1><p>disabled provider hidden</p>",
            "/admin": "<h1>Admin Dashboard</h1><p>users resources</p>",
            "/jobs": "<h1>Jobs Dashboard</h1><p>queued retry dead-letter</p>",
            "/notifications": "<h1>Notifications</h1><p>inbox outbox preferences</p>",
            "/search": "<h1>Search</h1><p>query results reindex status</p>",
            "/storage": "<h1>Storage</h1><p>collections objects upload</p>",
            "/ops": "<h1>Ops</h1><p>health metrics redacted</p>",
        }
        if path in pages:
            self.write(200, pages[path].encode("utf-8"))
            return
        if path == "/admin/protected":
            self.write_json(403, {"error": "route_policy_denied"})
            return
        if path == "/assets/auth.css":
            self.write(200, b".auth { display: block; }\n", "text/css")
            return
        self.write_json(404, {"error": "not_found"})

    def handle_data_get(self, path: str) -> None:
        if path == "/migrations":
            self.write_json(200, {"applied": ["001_create_records"], "status": "current"})
            return
        if path == "/records":
            self.write_json(200, {"records": [{"id": 1, "name": "alpha"}, {"id": 2, "name": "beta"}], "order": "id"})
            return
        if path == "/records/1":
            self.write_json(200, {"id": 1, "name": "alpha", "hydratedPrimaryKey": True})
            return
        if path == "/orm/descriptors":
            self.write_json(200, {"models": ["Record"], "relations": [], "backend": "fixture"})
            return
        self.write_json(404, {"error": "not_found"})

    def handle_data_post(self, path: str) -> None:
        if path != "/records":
            self.write_json(404, {"error": "not_found"})
            return
        fields = parse_qs(self.read_body())
        name = fields.get("name", [""])[0]
        if not name:
            self.write_json(422, {"error": "validation_failed", "field": "name"})
            return
        self.write_json(201, {"id": 3, "name": name, "transaction": "committed"})


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a Phase 37 acceptance fixture site")
    parser.add_argument("--site", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    log = open(args.log, "a", encoding="utf-8")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Phase37Handler)
    server.site = args.site  # type: ignore[attr-defined]
    server.log = log  # type: ignore[attr-defined]
    try:
        server.serve_forever()
    finally:
        log.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
