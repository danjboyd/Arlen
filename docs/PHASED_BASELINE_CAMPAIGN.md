# Phase D Baseline Campaign

Status: Complete (2026-02-24)  
Last updated: 2026-02-24

Related docs:
- `docs/COMPETITIVE_BENCHMARK_ROADMAP.md`
- `docs/PHASEB_PARITY_CHECKLIST_FASTAPI.md`
- `docs/PHASEC_BENCHMARK_PROTOCOL.md`
- `tests/performance/protocols/phased_baseline_campaign.json`
- `tests/performance/run_phased_campaign.py`

## 1. Objective

Execute the first full baseline campaign for approved Arlen-vs-FastAPI scenarios with:

- enforced parity gate before timing
- fixed concurrency-ladder protocol
- per-scenario comparison tables
- machine-readable raw artifact bundle for audit/review

## 2. Campaign Matrix

Protocol file:

- `tests/performance/protocols/phased_baseline_campaign.json`

Pair definitions:

- `comparison_http`: Arlen `comparison_http` vs FastAPI `fastapi_comparison_http`
- `middleware_heavy`: Arlen `middleware_heavy` vs FastAPI `fastapi_middleware_heavy` (pair ladder override: `1,4`)

The middleware-heavy ladder is intentionally constrained pending Phase E triage of higher-concurrency stability behavior in Arlen.

Claim targets:

- `C01`: `comparison_http:healthz`
- `C02`: `comparison_http:api_status`
- `C03`: `middleware_heavy:api_echo`

## 3. Execution

Run Phase D campaign:

```bash
make perf-phased
```

Direct runner:

```bash
python3 tests/performance/run_phased_campaign.py
```

Execution behavior:

1. Builds `boomhauer`.
2. Creates/updates FastAPI venv (`build/venv/fastapi_parity`) and installs `tests/performance/fastapi_reference/requirements.txt`.
3. Runs Phase B parity check before benchmarks.
4. Runs warmup + measured benchmark passes for both frameworks across the full ladder.
5. Generates comparison tables, methodology note, report JSON, and raw artifact bundle.

Optional overrides:

- `ARLEN_PHASED_CONCURRENCY_LIST` (comma-separated)
- `ARLEN_PHASED_WARMUP_REQUESTS`
- `ARLEN_PHASED_WARMUP_REPEATS`
- `ARLEN_PHASED_MEASURED_REQUESTS`
- `ARLEN_PHASED_MEASURED_REPEATS`
- `ARLEN_PHASED_SKIP_BUILD=1`
- `ARLEN_PHASED_SKIP_PARITY=1` (not recommended for publication runs)
- `ARLEN_FASTAPI_VENV` (custom venv path)

## 4. Artifacts

Per run:

- `build/perf/phased/runs/<run_id>/phased_campaign_report.json`
- `build/perf/phased/runs/<run_id>/phased_framework_summary.csv`
- `build/perf/phased/runs/<run_id>/phased_comparison.csv`
- `build/perf/phased/runs/<run_id>/phased_comparison.md`
- `build/perf/phased/runs/<run_id>/phased_methodology.md`
- `build/perf/phased/runs/<run_id>/artifact_manifest.json`
- `build/perf/phased/runs/<run_id>/phased_raw_artifacts.tar.gz`

Latest pointers:

- `build/perf/phased/latest_campaign_report.json`
- `build/perf/phased/latest_comparison.csv`
- `build/perf/phased/latest_comparison.md`
- `build/perf/phased/latest_methodology.md`

Latest verification:

- date: 2026-02-24
- command: `make perf-phased`
- result: pass
