# Runtime Concurrency Gate

This gate validates request/session lifecycle invariants that have historically regressed under concurrency pressure.

## Local Execution

```bash
bash ./tools/ci/run_runtime_concurrency_gate.sh
```

The gate builds `boomhauer` and runs `tools/ci/runtime_concurrency_probe.py` against:

1. `concurrent` dispatch mode
2. `serialized` dispatch mode (production default)

Each mode validates:

- websocket upgrade + echo roundtrip
- websocket channel fanout path
- SSE stream delivery under churn
- keep-alive/connection-close behavior appropriate to mode
- mixed slow/fast request workload under concurrent clients
- post-stress readiness/health recovery
- controlled startup/shutdown overlap with active traffic
- route-surface JSON/HTML contract checks (`/`, `/about`, `/api/status`, `/api/echo/:name`)
- data-layer API contract checks (`/api/db/items` read/write validation and error-shape contracts)

## Runtime Limits Covered

These runtime limits are now first-class config/env keys:

- `runtimeLimits.maxConcurrentHTTPWorkers`
  - env: `ARLEN_MAX_HTTP_WORKERS`
- `runtimeLimits.maxQueuedHTTPConnections`
  - env: `ARLEN_MAX_QUEUED_HTTP_CONNECTIONS`
- `runtimeLimits.maxRealtimeTotalSubscribers`
  - env: `ARLEN_MAX_REALTIME_SUBSCRIBERS`
- `runtimeLimits.maxRealtimeChannelSubscribers`
  - env: `ARLEN_MAX_REALTIME_SUBSCRIBERS_PER_CHANNEL`

Legacy `MOJOOBJC_*` env aliases are supported for each key.

## Deterministic Backpressure Reasons

Runtime overload responses use `503` plus `X-Arlen-Backpressure-Reason`. Key reasons covered by
tests/gates include:

- `http_session_limit`
- `http_worker_queue_full`
- `websocket_session_limit`
- `realtime_channel_subscriber_limit`
- `realtime_total_subscriber_limit`

## Sanitizer Policy

- Blocking lane (`asan_ubsan_blocking`) runs via:

```bash
make ci-sanitizers
```

The gate now enforces:

- suppression registry validation (`tests/fixtures/sanitizers/phase9h_suppressions.json`)
- runtime-critical probe coverage (routing, render, realtime, data-layer, lifecycle)
- Phase 9H confidence artifact generation (`build/release_confidence/phase9h/`)

- TSAN lane (`tsan_experimental`) remains non-blocking and can be executed directly:

```bash
bash ./tools/ci/run_phase5e_tsan_experimental.sh
```

TSAN writes retained artifacts under `build/sanitizers/tsan/` (log + summary JSON) for triage.

Suppression lifecycle rules are documented in:

- `docs/SANITIZER_SUPPRESSION_POLICY.md`

## Fault Injection

Phase 9I adds deterministic runtime seam fault scenarios:

```bash
make ci-fault-injection
```

This command exercises parser/dispatcher, websocket lifecycle, and runtime stop/start boundaries and writes triage artifacts to `build/release_confidence/phase9i`.
