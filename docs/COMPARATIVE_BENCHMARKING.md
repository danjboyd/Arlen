# Comparative Benchmarking

Status: Source of truth split between in-repo regression gates and the sibling `ArlenBenchmarking` publication harness
Last updated: 2026-03-21

## 1. Current State

- Arlen's original in-repo comparative benchmark track reached Phase D on 2026-02-24.
- The broader comparative/publication benchmark program now lives in the sibling repository at `../ArlenBenchmarking`.
- That external program currently reports:
  - non-DB track: `Phase 5 PACKAGE COMPLETE` on 2026-02-25
  - DB extension track: `Phase 9 PACKAGE COMPLETE` on 2026-02-25
- Remaining work in that external program is approval/sign-off and future refreshes, not missing benchmark-harness implementation.

## 2. Responsibility Split

Arlen repo responsibilities:

- performance regression gates and baselines used during normal development
- local/manual macro perf smoke lane (`make ci-perf-smoke`)
- blocking quality perf coverage (`make ci-quality`)
- in-repo microbenchmark gates (`make ci-json-perf`, `make ci-dispatch-perf`, `make ci-http-parse-perf`, `make ci-blob-throughput`)
- historical Arlen-vs-FastAPI parity/protocol/campaign artifacts (`make parity-phaseb`, `make perf-phasec`, `make perf-phased`)

Sibling `ArlenBenchmarking` responsibilities:

- multi-framework comparator implementations and harness orchestration
- scenario manifests and canonical benchmark configs for comparative claims
- report-generation and website-publication packages
- downloadable raw benchmark evidence bundles and versioned benchmark history
- approval workflow for benchmark language and claim publication

Imported lightweight contracts kept in Arlen:

- `tests/fixtures/benchmarking/comparative_scenarios.v1.json`
- `tests/fixtures/benchmarking/comparative_scenarios.db.v1.json`
- `tests/fixtures/benchmarking/comparative_benchmark_contract.v1.json`

These fixtures intentionally mirror only durable contract data from `../ArlenBenchmarking`. Arlen does not vendor the comparator apps, report archives, or publish runners.

## 3. Historical Docs In This Repo

These documents are preserved as the historical in-repo benchmark track that seeded the later external program:

- `docs/COMPETITIVE_BENCHMARK_ROADMAP.md`
- `docs/internal/BENCHMARK_HANDOFF_2026-02-24.md`
- `docs/internal/PHASEB_PARITY_CHECKLIST_FASTAPI.md`
- `docs/internal/PHASEC_BENCHMARK_PROTOCOL.md`
- `docs/internal/PHASED_BASELINE_CAMPAIGN.md`

## 4. Operational Rule

- Use Arlen repo perf gates to catch regressions in framework development.
- Use `../ArlenBenchmarking` when the task is cross-framework comparison, reporting, or website-ready publication evidence.
- If portable manifests/config/report schemas from `../ArlenBenchmarking` become generally useful inside Arlen, copy only those lightweight contracts in-repo; keep external framework implementations and large comparative report archives out of this repo.
- `make ci-docs` validates the imported contract pack through `tools/ci/check_benchmark_contracts.py` so the in-repo copies do not silently drift.
