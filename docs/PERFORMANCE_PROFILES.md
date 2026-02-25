# Performance Profiles and Trends

Phase 3C extends Arlen perf coverage from a single gate into profile-based trend tracking.

## 1. Profile Pack

Profiles live in `tests/performance/profiles/`:

- `default`
- `middleware_heavy`
- `template_heavy`
- `api_reference`
- `migration_sample`
- `comparison_http`
- `fastapi_comparison_http`
- `fastapi_middleware_heavy`

Each profile defines server target, launch env, readiness path, and scenario list.

## 2. Running Perf

Default gate:

```bash
make perf
```

Specific profile:

```bash
ARLEN_PERF_PROFILE=template_heavy make perf
```

Fast local path:

```bash
ARLEN_PERF_FAST=1 ARLEN_PERF_SKIP_GATE=0 ARLEN_PERF_REQUESTS=40 make perf
```

External comparison path (production-style config, reduced logging overhead, concurrent clients):

```bash
ARLEN_PERF_PROFILE=comparison_http ARLEN_PERF_SKIP_GATE=1 make perf
```

Optional concurrency override (all profiles):

```bash
ARLEN_PERF_CONCURRENCY=8 ARLEN_PERF_PROFILE=comparison_http ARLEN_PERF_SKIP_GATE=1 make perf
```

Phase C standardized benchmark protocol (warmup + concurrency ladder + metadata artifacts):

```bash
make perf-phasec
```

Protocol contract and artifacts are documented in `docs/PHASEC_BENCHMARK_PROTOCOL.md`.

Phase D standardized baseline campaign (parity + Arlen/FastAPI matrix + comparison artifacts):

```bash
make perf-phased
```

Campaign contract and artifacts are documented in `docs/PHASED_BASELINE_CAMPAIGN.md`.

## 3. Baselines and Policy

Per-profile baseline files:

- `tests/performance/baselines/<profile>.json`

Per-profile policy files:

- `tests/performance/policies/<profile>.json`

## 4. Trend Outputs

Generated on each run:

- `build/perf/latest_trend.json`
- `build/perf/latest_trend.md`

Historical archives:

- `build/perf/history/<profile>/`

The trend report summarizes drift for `p50/p95/p99`, throughput, and memory growth against recent history.
