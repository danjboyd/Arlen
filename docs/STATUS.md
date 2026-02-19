# Arlen Status Checkpoint

Last updated: 2026-02-19

## Current Milestone State

- Phase 1: complete
- Phase 2A: complete
- Phase 2B: complete
- Phase 2C: complete (2026-02-19)
- Phase 2D: complete (2026-02-19)
- Phase 3: planned

## Completed Today (2026-02-19)

- Closed EOC v1 spec-conformance gaps:
  - transpiler rewrite for sigil locals (`$name`) with strict syntax checks
  - runtime local lookup helper and strict render modes (`strict locals`, `strict stringify`)
  - strict failure diagnostics include template file/line/column metadata
  - regression coverage for sigil locals, method-call expressions, and strict-mode failures
- Delivered routing/content-negotiation parity baseline:
  - nested route groups with inherited prefix/guard/formats
  - format-aware route matching and request format stash (`Accept` + extension heuristics)
  - route guard action contract and structured reject/failure handling
  - API-only mode defaults (`serveStatic=NO`, `logFormat=json`) with env overrides
- Reduced generated app/controller boilerplate:
  - added framework runner entrypoint (`ALNRunAppMain`) for full/lite scaffolds
  - added concise stash/render helpers in `ALNController`
  - scaffolds now default to zero-boilerplate EOC locals usage (`<%= $title %>`)
- Expanded `arlen` CLI ergonomics:
  - added `generate endpoint`
  - added generator options: `--route`, `--method`, `--action`, `--template`, `--api`
  - added automatic route wiring into `src/main.m` / `app_lite.m`
  - added `arlen check` (`make check` wrapper)
- Established compiled deployment baseline artifacts and workflows:
  - immutable release packaging script (`tools/deploy/build_release.sh`)
  - activation script (`tools/deploy/activate_release.sh`)
  - rollback script (`tools/deploy/rollback_release.sh`)
  - built-in `/healthz`, `/readyz`, `/livez` endpoints
  - deployment smoke integration test coverage
- Hardened perf regression gate:
  - `make check` now runs unit + integration + perf gate
  - repeated-run, median-based perf aggregation
  - expanded guardrails: endpoint p95, throughput floor, memory growth
  - baseline metadata + explicit update policy (`ARLEN_PERF_UPDATE_BASELINE=1`)

## Verification State

- `make test-unit`: passing (2026-02-19)
- `make test-integration`: passing (2026-02-19)
- `make check`: passing (2026-02-19)
  - perf gate passed for `healthz`, `api_status`, and `root`
- PostgreSQL-backed tests remain gated by `ARLEN_PG_TEST_DSN`.

## Next Session Focus

1. Start Phase 3A (observability + extension surface): metrics endpoint and plugin/lifecycle contracts.
2. Expand API testing ergonomics toward parity matrix Phase 3A goals.
3. Begin deployment runbook automation hardening and release-trend reporting groundwork.
