# Benchmark Handoff (2026-02-24 EOD)

Status snapshot:

- Competitive benchmark phases complete: `A`, `B`, `C`, `D`
- Remaining phases: `E`, `F`
- Roadmap state: `docs/COMPETITIVE_BENCHMARK_ROADMAP.md` reflects Phase D complete and Phase E-F pending

## Latest Verified Run

- command: `make perf-phased`
- run_id: `20260224T233744Z`
- timestamp_utc: `2026-02-24T23:39:06Z`
- parity gate: pass (`C01-C05`)

Primary artifacts:

- report: `build/perf/phased/latest_campaign_report.json`
- comparison csv: `build/perf/phased/latest_comparison.csv`
- comparison markdown: `build/perf/phased/latest_comparison.md`
- methodology note: `build/perf/phased/latest_methodology.md`
- raw artifact bundle: `build/perf/phased/runs/20260224T233744Z/phased_raw_artifacts.tar.gz`

## Claim Snapshot (from latest report)

- `C01` (`comparison_http:healthz`, c=32):
  - Arlen p95 `2.491 ms`, FastAPI p95 `23.370 ms`
  - Arlen `1169.52 req/s`, FastAPI `1052.46 req/s`
- `C02` (`comparison_http:api_status`, c=32):
  - Arlen p95 `1.870 ms`, FastAPI p95 `18.611 ms`
  - Arlen `1125.77 req/s`, FastAPI `1049.23 req/s`
- `C03` (`middleware_heavy:api_echo`, c=4):
  - Arlen p95 `1.187 ms`, FastAPI p95 `2.476 ms`
  - Arlen `553.52 req/s`, FastAPI `486.05 req/s`

## Known Risk / Phase E Entry Point

- `middleware_heavy` at higher concurrency caused Arlen server segfault during baseline execution.
- Temporary protocol guardrail applied: pair ladder constrained to `1,4` in `tests/performance/protocols/phased_baseline_campaign.json`.
- This issue is queued for Phase E triage before claim finalization for higher-concurrency middleware-heavy scenarios.

## Morning Resume Checklist

1. Reproduce and isolate the `middleware_heavy` high-concurrency crash (`c>=8`) under the same Phase D harness.
2. Implement and validate runtime fix in Arlen.
3. Add regression coverage for the crash path.
4. Re-run `make perf-phased` with restored middleware-heavy ladder if stable.
5. Start Phase F draft using latest comparison/methodology artifacts.
