# Phase C Benchmark Protocol

Status: Complete (2026-02-24)  
Last updated: 2026-02-24

Related docs:
- `docs/COMPETITIVE_BENCHMARK_ROADMAP.md`
- `docs/PERFORMANCE_PROFILES.md`
- `tests/performance/protocols/phasec_comparison_http.json`
- `tests/performance/run_phasec_protocol.py`

## 1. Objective

Standardize benchmark execution for comparison scenarios with:

- fixed host/profile/port contract
- explicit warmup phase before measured runs
- required concurrency ladder execution
- repeat-based median metrics and archived artifacts
- machine/runtime metadata capture for reproducibility

## 2. Default Protocol

Protocol file:

- `tests/performance/protocols/phasec_comparison_http.json`

Defaults:

- profile: `comparison_http`
- host: `127.0.0.1`
- port: `3301`
- concurrency ladder: `1,4,8,16,32`
- warmup: `30` requests x `1` repeat per ladder step
- measured: `120` requests x `3` repeats per ladder step

## 3. Execution

Run the protocol:

```bash
make perf-phasec
```

Direct runner:

```bash
python3 tests/performance/run_phasec_protocol.py
```

Optional overrides:

- `ARLEN_PHASEC_PROFILE`
- `ARLEN_PHASEC_HOST`
- `ARLEN_PHASEC_PORT`
- `ARLEN_PHASEC_CONCURRENCY_LIST` (comma-separated)
- `ARLEN_PHASEC_WARMUP_REQUESTS`
- `ARLEN_PHASEC_WARMUP_REPEATS`
- `ARLEN_PHASEC_MEASURED_REQUESTS`
- `ARLEN_PHASEC_MEASURED_REPEATS`

## 4. Artifacts

Per run:

- `build/perf/phasec/runs/<run_id>/phasec_protocol_report.json`
- `build/perf/phasec/runs/<run_id>/phasec_summary.csv`
- `build/perf/phasec/runs/<run_id>/ladder/c*/artifacts/*`
- `build/perf/phasec/runs/<run_id>/ladder/c*/logs/*`

Latest pointer:

- `build/perf/phasec/latest_protocol_report.json`

Report includes:

- protocol configuration and execution parameters
- per-concurrency measured reports
- machine metadata (`platform`, `cpu_count`, `cpu_model`, memory)
- tool version metadata (`python`, `clang`, `curl`, `bash`)
- git commit metadata

Latest verification:

- date: 2026-02-24
- command: `make perf-phasec`
- result: pass
