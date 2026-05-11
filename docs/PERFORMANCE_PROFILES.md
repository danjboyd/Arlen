# Performance Profiles and Trends

Arlen extends perf coverage from a single gate into profile-based trend tracking.

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

CI smoke gate:

```bash
make ci-perf-smoke
```

This runs the checked-in `default` and `template_heavy` profiles with the same
baseline/policy comparison logic as `make perf`, then archives artifacts under
`build/perf/ci_smoke/`. It is a lighter standalone subset of the broader
multi-profile macro perf coverage already exercised by `make ci-quality`, so it
remains a local/manual triage lane rather than a separate GitHub workflow.

Specific profile:

```bash
ARLEN_PERF_PROFILE=template_heavy make perf
```

Fast local path:

```bash
ARLEN_PERF_FAST=1 ARLEN_PERF_SKIP_GATE=0 ARLEN_PERF_REQUESTS=40 make perf
```

Smoke-gate overrides:

```bash
ARLEN_PERF_SMOKE_PROFILES=default,template_heavy ARLEN_PERF_SMOKE_REPEATS=3 make ci-perf-smoke
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

Protocol contract and artifacts are documented in `docs/internal/PHASEC_BENCHMARK_PROTOCOL.md`.

Phase D standardized baseline campaign (parity + Arlen/FastAPI matrix + comparison artifacts):

```bash
make perf-phased
```

Campaign contract and artifacts are documented in `docs/internal/PHASED_BASELINE_CAMPAIGN.md`.

## 3. Baselines and Policy

Per-profile baseline files:

- `tests/performance/baselines/<profile>.json`
- `tests/performance/baselines/iep-apt/<profile>.json` for the current
  self-hosted runner hardware

Per-profile policy files:

- `tests/performance/policies/<profile>.json`

Optional harness overrides:

- `ARLEN_PERF_BASELINE_ROOT=<path>` swaps the per-profile baseline directory
- `ARLEN_PERF_POLICY_ROOT=<path>` swaps the per-profile policy directory

## 4. Trend Outputs

Generated on each run:

- `build/perf/latest_trend.json`
- `build/perf/latest_trend.md`

Historical archives:

- `build/perf/history/<profile>/`

The trend report summarizes drift for `p50/p95/p99`, throughput, and memory growth against recent history.
