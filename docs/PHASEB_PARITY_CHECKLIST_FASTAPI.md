# Phase B Parity Checklist (Arlen vs FastAPI)

Status: Complete (2026-02-24)  
Last updated: 2026-02-24

Related docs:
- `docs/COMPETITIVE_BENCHMARK_ROADMAP.md`
- `docs/PERFORMANCE_PROFILES.md`
- `docs/ARLEN_FOR_FASTAPI.md`
- `tests/performance/check_parity_fastapi.py`
- `tests/performance/fastapi_reference/app.py`

## 1. Objective

Provide executable parity validation for frozen v1 benchmark scenarios before comparative performance claims.

Phase B acceptance rule:

- parity checks pass for both frameworks before benchmark execution

## 2. Scenario Matrix

| Claim ID | Scenario | Arlen endpoint | FastAPI endpoint | Status/shape parity requirements |
| --- | --- | --- | --- | --- |
| C01 | Health check tiny payload | `GET /healthz` | `GET /healthz` | `200`, `text/plain`, body `ok\n` |
| C02 | API status JSON | `GET /api/status` | `GET /api/status` | `200`, JSON object with `ok=true`, numeric `timestamp`, string `server` |
| C03 | Middleware/API echo path | `GET /api/echo/hank` | `GET /api/echo/hank` | `200`, exact JSON payload parity for `name` and `path` |
| C04 | Keep-alive reuse behavior | same connection: `/healthz` then `/api/status` | same connection: `/healthz` then `/api/status` | first response does not force close; second response succeeds on same socket |
| C05 | Backpressure under constrained sessions | `ARLEN_MAX_HTTP_SESSIONS=1` overload probe | `uvicorn --limit-concurrency 2` overload probe | deterministic overload behavior observed + post-overload recovery to `200 /healthz` |

## 3. Execution

Single command:

```bash
make parity-phaseb
```

What it does:

1. Creates/uses venv at `build/venv/fastapi_parity`.
2. Installs FastAPI + uvicorn from `tests/performance/fastapi_reference/requirements.txt`.
3. Builds Arlen `boomhauer`.
4. Runs executable parity checks in `tests/performance/check_parity_fastapi.py`.
5. Writes report JSON to `build/perf/parity_fastapi_latest.json`.

## 4. Artifacts

- parity report: `build/perf/parity_fastapi_latest.json`
- runtime logs: `build/perf/parity_logs/*.log`

The report includes per-claim pass/fail fields and probe details for C01-C05.

Latest verification:

- date: 2026-02-24
- command: `make parity-phaseb`
- result: pass
