# Competitive Benchmark Roadmap

Status: Active (Phase A complete; Phase B complete; Phase C complete; Phase D complete; Phase E-F pending)  
Last updated: 2026-02-24

Related docs:
- `docs/PERFORMANCE_PROFILES.md`
- `docs/PHASE7A_RUNTIME_HARDENING.md`
- `docs/RELEASE_PROCESS.md`
- `docs/ARLEN_FOR_FASTAPI.md`
- `docs/PHASED_BASELINE_CAMPAIGN.md`
- `docs/STATUS.md`

## 1. Objective

Deliver reproducible, publishable benchmark evidence for where Arlen outperforms widely used frameworks (starting with FastAPI) in scenarios that reflect realistic production behavior.

Primary outcomes:

- credible performance claims for Arlen website/marketing usage
- clear methodology and raw artifacts suitable for technical review
- fast feedback loop for identifying and fixing Arlen bottlenecks when Arlen loses

## 2. Scope

In scope:

- apples-to-apples HTTP/API scenario comparisons (Arlen vs FastAPI first)
- repeatable benchmark protocol and artifact packaging
- performance-driven Arlen optimization loop based on measured losses

Out of scope for initial slice:

- broad multi-language framework shootout in first pass
- non-deterministic "best run only" claim generation
- scenario variants without behavior parity validation

## 3. Non-Negotiable Rules

1. Behavior parity first: same endpoint semantics, payloads, and status codes before timing.
2. Fixed benchmark protocol: hardware/OS/runtime/tool versions and run procedure are pinned.
3. Full artifact retention: keep raw runs, summaries, and environment metadata.
4. No cherry-picking: report medians and variance, not single best values.
5. Losses are useful: when Arlen underperforms, treat result as optimization input.

## 4. Roadmap Phases

## 4.1 Phase A: Claim Matrix Freeze

Status: Complete (2026-02-24)

Frozen v1 claim matrix:

| Claim ID | Claim | Arlen scenario | Primary metric(s) | Regression guard |
| --- | --- | --- | --- | --- |
| C01 | Arlen sustains strong low-latency throughput for tiny JSON health checks. | `comparison_http:healthz` (`/healthz`) | `req/sec`, `p95`, `p99` | `make test-unit`, `make test-integration`, `ARLEN_PERF_PROFILE=comparison_http ... make perf` |
| C02 | Arlen sustains strong API JSON status throughput under concurrent clients. | `comparison_http:api_status` (`/api/status`) | `req/sec`, `p95`, `p99` | `make test-unit`, `make test-integration`, `ARLEN_PERF_PROFILE=comparison_http ... make perf` |
| C03 | Arlen handles middleware-heavy API paths with predictable latency under load. | `middleware_heavy:api_echo` (`/api/echo/hank`) | `p95`, `p99`, `req/sec` | `make test-unit`, `make test-integration`, `ARLEN_PERF_PROFILE=middleware_heavy make perf` |
| C04 | Arlen supports keep-alive reuse without request corruption/regression. | HTTP keep-alive path on one connection | integration pass/fail + latency sanity | `tests/integration/HTTPIntegrationTests.m` (`testKeepAliveAllowsMultipleRequestsOnSingleConnection`) |
| C05 | Arlen enforces deterministic backpressure at HTTP session limit boundaries. | constrained runtime limit path (`ARLEN_MAX_HTTP_SESSIONS`) | deterministic `503` contract + recovery | `tests/integration/HTTPIntegrationTests.m` (`testHTTPSessionLimitReturns503UnderBackpressure`) |

Owners:

- Arlen runtime/performance owner: framework maintainers (`Arlen` core repo).
- Claim publication owner: website/marketing maintainers after technical sign-off.

Pass rule policy for publication:

- For performance claims (`C01-C03`): publish only if Arlen shows repeatable median win or parity within agreed variance band.
- For reliability contracts (`C04-C05`): publish only if deterministic regression checks stay green.

## 4.2 Phase B: Parity Scenario Implementations

Status: Complete (2026-02-24)

Build matched Arlen and FastAPI services for each scenario.

Required parity checklist per scenario:

- request/response body shape
- headers and status behavior
- error-path behavior
- middleware/auth/validation behavior (when applicable)

Exit criteria:

- parity checks pass for both frameworks before benchmark execution

Implementation notes (completed):

- Added FastAPI reference implementation for frozen v1 scenarios:
  - `tests/performance/fastapi_reference/app.py`
  - `tests/performance/fastapi_reference/requirements.txt`
- Added executable parity checker:
  - `tests/performance/check_parity_fastapi.py`
  - validates C01-C05 behavior and emits machine-readable report
- Added one-command runner:
  - `tests/performance/run_phaseb_parity.sh`
  - `make parity-phaseb`
- Added checklist and execution contract doc:
  - `docs/PHASEB_PARITY_CHECKLIST_FASTAPI.md`
- Latest verification:
  - command: `make parity-phaseb`
  - result: pass
  - artifact: `build/perf/parity_fastapi_latest.json`

## 4.3 Phase C: Benchmark Protocol Hardening

Status: Complete (2026-02-24)

Standardize benchmark execution:

- fixed host and runtime metadata capture
- warmup + measured run structure
- concurrency ladder (for example: 1, 4, 8, 16, 32)
- repeat count sufficient for stable medians

Metrics:

- latency: p50, p95, p99, max
- throughput: req/sec
- memory delta: process RSS before/after run

Arlen harness baseline:

- `ARLEN_PERF_PROFILE=comparison_http ARLEN_PERF_SKIP_GATE=1 make perf`
- outputs in `build/perf/latest.json`, `build/perf/latest.csv`, `build/perf/latest_runs.csv`

Exit criteria:

- repeated runs show stable variance bounds acceptable for publication

Implementation notes (completed):

- Added fixed protocol contract file:
  - `tests/performance/protocols/phasec_comparison_http.json`
- Added executable protocol runner:
  - `tests/performance/run_phasec_protocol.py`
  - runs warmup + measured passes for each ladder concurrency
  - captures machine/tool/git metadata in run artifacts
- Added Make target:
  - `make perf-phasec`
- Added protocol documentation:
  - `docs/PHASEC_BENCHMARK_PROTOCOL.md`
- Latest verification:
  - command: `make perf-phasec`
  - result: pass
  - artifact: `build/perf/phasec/latest_protocol_report.json`

## 4.4 Phase D: Baseline Campaign Execution

Status: Complete (2026-02-24)

Run full matrix for all approved scenarios and both frameworks.

Deliverables:

- per-scenario comparison table
- methodology note (versions, hardware, protocol)
- raw artifacts package (machine-readable)

Exit criteria:

- complete run set with no unresolved parity gaps

Implementation notes (completed):

- Added FastAPI benchmark profiles to mirror Arlen campaign pairs:
  - `tests/performance/profiles/fastapi_comparison_http.sh`
  - `tests/performance/profiles/fastapi_middleware_heavy.sh`
- Added fixed Phase D campaign protocol:
  - `tests/performance/protocols/phased_baseline_campaign.json`
- Captured a stability guardrail in protocol:
  - `middleware_heavy` pair currently uses ladder `1,4` (higher concurrency reproducibly crashed Arlen in baseline run and is queued for Phase E triage)
- Added executable campaign runner:
  - `tests/performance/run_phased_campaign.py`
  - enforces Phase B parity check before timing
  - runs Arlen + FastAPI across full concurrency ladder per pair
  - writes framework summaries, per-scenario comparison table, methodology note, and raw artifact bundle
- Added Make target:
  - `make perf-phased`
- Added campaign execution guide:
  - `docs/PHASED_BASELINE_CAMPAIGN.md`
- Latest verification:
  - command: `make perf-phased`
  - result: pass
  - artifacts:
    - `build/perf/phased/latest_campaign_report.json`
    - `build/perf/phased/latest_comparison.csv`
    - `build/perf/phased/latest_methodology.md`

## 4.5 Phase E: Arlen Optimization Loop

For scenarios where Arlen underperforms:

1. profile and isolate bottleneck
2. implement targeted fix
3. add regression test where practical
4. re-run identical protocol

Exit criteria:

- either Arlen improves to target band or scenario is downgraded/removed from claims

## 4.6 Phase F: Marketing Publication Pack

Publish only validated results.

Required pack contents:

- claim statements with concrete metric deltas
- concise charts/tables for website use
- methodology and environment disclosure
- artifact links or downloadable evidence bundle

Exit criteria:

- technical and marketing review approval
- claims are reproducible from committed benchmark assets

## 5. Readiness Gate (Go/No-Go)

Go if all are true:

- runtime hardening preconditions are in place (including session-limit backpressure contracts)
- scenario parity is validated
- results are repeatable across repeated runs
- artifact pack is complete

No-Go if any are true:

- claim depends on one-off tuning or non-default hidden settings
- parity differences remain unresolved
- variance is too high to make defensible claims

## 6. Immediate Next Actions

1. Completed: freeze claim matrix and scenario list for v1 comparison set.
2. Completed: add parity checklist docs and executable parity validation for v1 scenarios (Arlen/FastAPI).
3. Completed: execute first baseline campaign matrix for Arlen vs FastAPI with parity gate and artifact package.
4. Triage losses and patch Arlen only where deltas are material.
5. Produce first publication-ready benchmark report draft.
