# Performance Profiles and Trends

Phase 3C extends Arlen perf coverage from a single gate into profile-based trend tracking.

## 1. Profile Pack

Profiles live in `tests/performance/profiles/`:

- `default`
- `middleware_heavy`
- `template_heavy`
- `api_reference`
- `migration_sample`

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
