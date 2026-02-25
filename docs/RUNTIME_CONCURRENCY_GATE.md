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
- keep-alive/connection-close behavior appropriate to mode
- mixed slow/fast request workload under concurrent clients
- post-stress readiness/health recovery

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

## Sanitizer Policy

- ASAN/UBSAN remain required via `make ci-sanitizers`.
- TSAN is provided as an experimental profile:

```bash
bash ./tools/ci/run_phase5e_tsan_experimental.sh
```

The TSAN run is non-blocking in CI and should be used to surface potential races early.
