# Arlen Status Checkpoint

Last updated: 2026-02-19

## Current Milestone State

- Phase 1: complete
- Phase 2A: complete
- Phase 2B: complete
- Phase 2C: complete (2026-02-19)
- Phase 2D: complete (2026-02-19)
- Phase 3A: complete (2026-02-19)
- Phase 3B: complete (2026-02-19)
- Phase 3C-3E: planned

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
- Executed Phase 3A platform slice:
  - metrics registry and `/metrics` endpoint with standardized request/runtime counters
  - route-level request/response schema contracts with coercion and deterministic validation errors
  - OpenAPI 3.1 generation and built-in docs endpoints (`/openapi.json`, `/.well-known/openapi.json`, `/openapi`)
  - auth baseline with bearer/JWT verification helpers, route scope/role checks, and context accessors
  - plugin/lifecycle contracts with startup/shutdown hooks and config-driven plugin loading
  - optional trace exporter hook for OpenTelemetry-style integration points
  - CLI plugin scaffolding (`arlen generate plugin`) and scaffold config defaults for `auth`/`openapi`/`plugins`
  - boomhauer watch-mode rebuild linker parity fix for OpenSSL-backed auth code (`-lcrypto`)
- Executed Phase 3B platform slice:
  - standardized data adapter contracts (`ALNDatabaseAdapter`/`ALNDatabaseConnection`) and adapter conformance harness
  - optional SQL builder (`ALNSQLBuilder`) with deterministic SQL/parameter snapshot coverage
  - optional DisplayGroup-style helper (`ALNDisplayGroup`) for sort/filter/batch adapter workflows
  - PostgreSQL adapter productized against adapter contracts plus optional GDL2 compatibility adapter (`ALNGDL2Adapter`)
  - opt-in session/page-state compatibility helper (`ALNPageState`) with default stateless behavior preserved
  - OpenAPI docs UX upgrade to interactive try-it-out explorer at `/openapi`, with `/openapi/viewer` fallback path
  - config/scaffold support for `database.adapter`, `openapi.docsUIStyle`, and `compatibility.pageStateEnabled`
  - integration coverage for interactive docs + representative API execution flow

## Verification State

- `make test-unit`: passing (2026-02-19)
- `make test-integration`: passing (2026-02-19)
- `make check`: passing (2026-02-19)
  - perf gate passed for `healthz`, `api_status`, and `root`
- PostgreSQL-backed tests remain gated by `ARLEN_PG_TEST_DSN`.

## Next Session Focus

1. Start Phase 3C distribution/release/doc maturity tranche.
2. Publish GSWeb-to-Arlen migration guide and side-by-side migrated reference app.
3. Publish API-first reference app for schema/OpenAPI/auth defaults.
4. Expand release/performance trend reporting automation:
   - endpoint-level trend outputs (`p50`/`p95`/`p99`)
   - workload-profile expansion for middleware-heavy and template-heavy scenarios
5. Add self-hosted Swagger UI docs option on top of `/openapi.json` while preserving current docs fallbacks.
