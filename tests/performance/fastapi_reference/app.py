#!/usr/bin/env python3
import asyncio
import time

from fastapi import FastAPI, Query
from fastapi.responses import HTMLResponse, PlainTextResponse

app = FastAPI(
    title="Arlen Phase B FastAPI Reference",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)

ROOT_HTML = """<h1>Arlen EOC Dev Server</h1>

<p class="template-note">template:multiline-ok</p>
<nav>
  <a href="/">Home</a>
  <a href="/about">About</a>
</nav>

<ul>
  <li>render pipeline ok</li>
  <li>request path: /</li>
</ul>
"""


@app.get("/healthz", response_class=PlainTextResponse)
def healthz() -> str:
    return "ok\n"


@app.get("/api/status")
def api_status() -> dict:
    return {
        "server": "boomhauer",
        "ok": True,
        "timestamp": time.time(),
    }


@app.get("/api/echo/{name}")
def api_echo(name: str) -> dict:
    return {
        "name": name,
        "path": f"/api/echo/{name}",
    }


@app.get("/", response_class=HTMLResponse)
def root() -> str:
    return ROOT_HTML


@app.get("/hold", response_class=PlainTextResponse)
async def hold(seconds: float = Query(default=1.2, ge=0.05, le=5.0)) -> str:
    await asyncio.sleep(seconds)
    return "hold\n"
