# Arlen Phase 2 Roadmap

Status: Phase 2A and Phase 2B complete; Phase 2C planned  
Last updated: 2026-02-18

Related docs:
- `docs/PHASE1_SPEC.md`
- `docs/ARLEN_CLI_SPEC.md`
- `docs/PHASE3_ROADMAP.md`

## 1. Objective

Close adoption-critical gaps so teams can run Arlen in production behind a reverse proxy with confidence.

## 2. Scope Summary

1. `propane` production server and worker lifecycle.
2. Production concurrency model and connection lifecycle controls.
3. HTTP completeness for common API workloads.
4. PostgreSQL-first data layer (`Arlen::Pg` analog).
5. Session/auth/security baseline.
6. Error experience and request validation ergonomics.

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

## 3.3 Phase 2C: Developer Experience Hardening

Deliverables:
- Rich development exception page with template/stack mapping.
- Production-safe structured errors with correlation IDs.
- Unified parameter access and explicit validation helpers.
- Standardized 4xx validation error shape for API responses.

Acceptance:
- Error-page and production-error contract tests pass.
- Validation coercion/rejection tests pass.

## 4. Key Decisions (Phase 2)

1. Runtime model: prefork vs threaded.  
Recommendation: prefork first for failure isolation and operational simplicity.

2. Database-first target.  
Recommendation: PostgreSQL first via `ALNPg`.

3. SQL abstraction timing.  
Recommendation: explicit SQL first; optional builder in Phase 3.

4. GDL2 scope.  
Recommendation: feasibility spike in 2B, full support deferred to Phase 3.

## 5. Performance and Quality Gates

- Unit + integration + stress tests for every subsystem.
- Benchmark output archived per CI run.
- Regression budgets for latency/throughput/memory.
- Security regressions for parser/session/CSRF/rate-limit features.
