# Arlen Phase 2 Roadmap

Status: Phase 2A, Phase 2B, Phase 2C, and Phase 2D complete  
Last updated: 2026-02-19

Related docs:
- `docs/PHASE1_SPEC.md`
- `docs/ARLEN_CLI_SPEC.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/PHASE3_ROADMAP.md`
- `docs/DEPLOYMENT.md`

## 1. Objective

Close adoption-critical gaps so teams can run Arlen in production behind a reverse proxy with confidence, while establishing a behavior-level parity baseline with Mojolicious for in-scope features.

## 2. Scope Summary

1. `propane` production server and worker lifecycle.
2. Production concurrency model and connection lifecycle controls.
3. HTTP completeness for common API workloads.
4. PostgreSQL-first data layer (`Arlen::Pg` analog).
5. Session/auth/security baseline.
6. Error experience and request validation ergonomics.
7. `boomhauer` compile-failure developer UX (non-crashing, rich diagnostics).
8. Compiled deployment contract baseline (release artifacts, migrate, health, rollback).
9. Performance instrumentation and regression-gate hardening.

## 3. Milestones

## 3.1 Phase 2A: Runtime Foundation (Completed 2026-02-18)

Delivered:
- Implemented `propane` prefork process manager.
- Added "propane accessories" config surface in app config + env overrides.
- Added graceful shutdown/reload and worker restart on crash.
- Added connection timeout and accept-loop back-pressure controls.
- Hardened request lifecycle with runtime limits and timeout handling.

Acceptance (met):
- Multi-worker integration tests pass.
- Graceful reload integration test passes under synthetic traffic.
- Crash/restart recovery integration test passes.

## 3.2 Phase 2B: Data + Security Core (Completed 2026-02-18)

Delivered:
- Implemented `ALNPg` core adapter:
  - explicit SQL + bind params
  - prepared statements
  - connection pooling
  - transaction helpers
- Added migration runner integration in `arlen` CLI:
  - `arlen migrate [--env <name>] [--dsn <connection_string>] [--dry-run]`
- Added cookie-session middleware and CSRF middleware.
- Added baseline rate-limiting middleware.
- Added security-header middleware with defaults enabled.
- Added built-in middleware auto-registration from app config.
- Added PostgreSQL unit/integration coverage (gated by `ARLEN_PG_TEST_DSN` for DB-backed cases).

SQL builder policy in Phase 2:
- Do not block this milestone on a full SQL abstraction DSL.
- Keep raw SQL as first-class API.
- Design DB interfaces so an optional SQL builder can be added in Phase 3.

GDL2 placement in Phase 2:
- No core dependency added in Phase 2B.
- Explicit SQL via `ALNPg` remains the default and first-class path.
- GDL2 feasibility work remains scoped as optional follow-up and is tracked for Phase 3.

Acceptance (met):
- PostgreSQL integration tests pass when `ARLEN_PG_TEST_DSN` is set.
- Session + CSRF middleware regression tests pass.
- CSRF rejection and rate-limit regression tests pass.
- Security-header middleware tests pass.

## 3.3 Phase 2C: Developer Experience Hardening (Completed 2026-02-19)

Delivered:
- Rich development exception page with template/stack mapping.
- `boomhauer` compile-failure behavior contract:
  - reload compile failures must not crash `boomhauer`
  - unified rendering for EOC transpile and Objective-C compile/link failures
  - HTML error page for browser requests
  - structured JSON error payload for API-oriented requests
  - diagnostics include stage, command, exit code, file/line/column, and source snippets when available
  - warnings are visible but collapsed by default
- Production-safe structured errors with correlation IDs.
- Unified parameter access and explicit validation helpers.
- Standardized `4xx` validation error shape for API responses.
- Close runtime timing coverage gaps:
  - add request `parse` and `response_write` stage timings
  - keep per-request timing keys deterministic across dynamic/static/error paths
- Enforce `performanceLogging` runtime switch:
  - when enabled, include timing headers and timing log payloads
  - when disabled, skip timing headers/payloads and stage timing overhead where practical

Acceptance (met):
- Compile-failure recovery tests pass (server remains alive and self-recovers after source fix).
- Error-page and JSON error contract tests pass.
- Production structured-error contract tests pass.
- Validation coercion/rejection tests pass.
- Stage timing contract tests pass for dynamic/static/error request paths.
- `performanceLogging` on/off behavior tests pass for headers and log payload shape.

Verification snapshot (2026-02-19):
- `make test-unit` passed.
- `make test-integration` passed.

## 3.4 Phase 2D: Parity Baseline + Deployment Contract (Completed 2026-02-19)

Delivered:
- Closed EOC implementation/spec gaps:
  - sigil local rewrite support (`$name`) in transpiler output
  - runtime local lookup and strict render modes (`strict locals`, `strict stringify`) per `V1_SPEC.md`
  - strict-mode failure diagnostics with template filename/line/column metadata
  - fixture/unit coverage for sigil locals, method-call usage, and strict-mode failures
  - default scaffold templates updated for zero-boilerplate locals
- Reduced generated app/controller boilerplate:
  - framework-runner entrypoint contract (`ALNRunAppMain`) for full/lite scaffolds
  - route-aware generation flows (`--route`, `--method`, `--action`, `--template`, `--api`)
  - placeholder route pattern support (for example `/user/admin/:id`) in concise generation flows
  - concise controller render/stash helpers while preserving explicit APIs
- Implemented remaining in-scope parity capabilities from `docs/FEATURE_PARITY_MATRIX.md`:
  - nested route groups/guards/conditions
  - content negotiation and format-aware rendering paths
  - API-only mode defaults
  - baseline HTTP/JSON flow regression coverage
- Established compiled deployment baseline:
  - immutable release artifact layout and metadata
  - explicit migration step in deployment workflow
  - readiness and liveness endpoint contract (`/readyz`, `/livez`)
  - production JSON logging defaults for API-only posture
  - rollback workflow through release selection scripts
- Published first deployment runbook baseline:
  - container-first operational path
  - VM/systemd operational path
- Hardened performance regression execution:
  - `make check` path runs unit + integration + perf gate
  - local fast path retained via perf script flags
  - perf gate expanded beyond single endpoint p95 to endpoint p95 + throughput floor + memory growth guardrails
  - repeated-run, median-based scenario comparison
  - baseline metadata and explicit baseline update policy

Acceptance (met):
- EOC transpiler/runtime behavior matches `V1_SPEC.md` sigil-local and strict render-mode semantics with regression coverage.
- Full/lite starter apps and generator-driven endpoint flows meet boilerplate-reduction targets.
- In-scope Phase 2 parity checklist items are implemented or explicitly classified in parity docs.
- Deployment smoke tests pass for release artifact build, activation, health checks, and rollback.
- Rolling reload behavior under `propane` remains validated with integration tests.
- `make check` passes with perf gate enabled.
- Perf harness regression checks validate endpoint latency, throughput, and memory guardrails.
- Baseline refresh/update workflow is documented and enforced through explicit update flag policy.

## 4. Key Decisions (Phase 2)

1. Runtime model: prefork vs threaded.  
Recommendation: prefork first for failure isolation and operational simplicity.

2. Database-first target.  
Recommendation: PostgreSQL first via `ALNPg`.

3. SQL abstraction timing.  
Recommendation: explicit SQL first; optional builder in Phase 3.

4. GDL2 scope.  
Recommendation: feasibility spike in 2B, full support deferred to Phase 3.

5. Parity model.  
Recommendation: behavior/capability parity for in-scope Mojolicious features, Cocoa-forward APIs.

6. Developer compile-failure UX in `boomhauer`.  
Recommendation: fail-safe dev server with rich HTML/JSON diagnostics instead of process crash.

7. Compiled deployment model.  
Recommendation: container-first with first-class VM/systemd support, immutable release artifacts, explicit migrate step, health endpoints, and rollback contract.

8. Performance gate enforcement.  
Recommendation: make perf regression checks release-blocking in CI while preserving an explicit fast local developer path.

## 5. Performance and Quality Gates

- Unit + integration + stress tests for every subsystem.
- Benchmark output archived per CI run.
- Regression budgets for latency/throughput/memory.
- Security regressions for parser/session/CSRF/rate-limit features.
- Compile-failure and structured-error contract regression tests for `boomhauer` and production paths.
- Capability-to-tests parity mapping for all in-scope Phase 2 parity items.
- Mandatory CI/release execution of perf regression gate via `make check`.
- Perf budgets include endpoint p95, throughput floor, and memory growth constraints.

## 6. Refactor Tracks Executed in Phase 2

1. Split `boomhauer` supervisor from build/worker execution path to guarantee non-crashing reload behavior.
2. Normalize error payload structures across transpiler/runtime/compiler failure surfaces.
3. Refactor route internals to support grouped routes, guards, and conditions without breaking existing route registration contracts.
4. Add reusable validation primitives and shared serialization for validation error responses.
5. Add explicit parse/write timing instrumentation points in HTTP request lifecycle code paths.
6. Wire `performanceLogging` configuration into runtime timing headers/log payload behavior.
7. Align transpiler/runtime local-variable semantics with `V1_SPEC.md` (`$name` rewrite + strict locals/stringify enforcement).
8. Consolidate app boot and route-generation ergonomics so common endpoint workflows avoid manual `main.m`/`app_lite.m` plumbing edits.
