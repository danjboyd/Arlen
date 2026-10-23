# Performance Profiles and Trends

Arlen extends perf coverage from a single gate into profile-based trend tracking.

## Response header construction

After initializing the GNUstep environment, run `make response-header-perf-bench`
and `./build/response-header-perf-bench 20000` (`.exe` on Windows). The optional
iteration argument defaults to 100000. Two thousand warmup responses precede
each measurement. The middleware case constructs and serializes default security
headers; dynamic32 inserts 32 headers in reverse order, including a Unicode
value. Output includes microseconds per response and serialized byte totals.

The security middleware and baseline static/error responses use private immutable
header snapshots validated once at configuration time. Public response setters
still validate every input; wire ordering, repeated headers and application
overrides retain their existing behavior. Dynamic middleware subclasses continue
to use their `responseHeaders` override per request.

On Windows CLANG64 toolchain 0.1.1, three 20000-response trials measured median
middleware construction at 37.950 before / 25.780 microseconds after (32.1% less
time), and dynamic32 at 101.950 / 94.566 (7.2% less time). Serialized totals were
identical: 7920000 and 22360000 bytes respectively. These local microbenchmarks
include response/context creation and serialization, not network latency, and
are evidence rather than a CI timing threshold.

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

`middleware_heavy` explicitly configures one propane process worker for its
direct `boomhauer` server, matching the process-local rate limiter's contract.
Sessions, CSRF, rate limits and security headers stay enabled; client
concurrency, scenarios, request counts and performance thresholds are unchanged.

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
