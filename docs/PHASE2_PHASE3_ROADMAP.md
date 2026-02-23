# Arlen Phase 2 + Phase 3 Roadmap Index

Status: Active (Phase 2A-2D complete; Phase 3A-3H complete; Phase 4A-4E complete; Phase 5A-5E complete; Phase 7A/7B/7C/7D initial slices implemented; Phase 7 follow-on planned)  
Last updated: 2026-02-23

This index points to the current roadmap documents:

- `docs/PHASE2_ROADMAP.md`
- `docs/PHASE3_ROADMAP.md`
- `docs/PHASE4_ROADMAP.md`
- `docs/PHASE5_ROADMAP.md`
- `docs/PHASE7_ROADMAP.md`
- `docs/FEATURE_PARITY_MATRIX.md`

## Summary

Phase 2 is focused on adoption-critical capabilities:
- `propane` and production runtime hardening (Phase 2A complete)
- data/security core (Phase 2B complete)
- developer error and validation ergonomics (Phase 2C complete)
- EOC spec-conformance parity tranche (Phase 2D complete: sigil locals + strict locals/stringify)
- generated app/controller boilerplate-reduction tranche (Phase 2D complete: runner entrypoint + route-aware generation + concise render defaults)
- in-scope parity baseline completion for routing/negotiation/API-only flows (Phase 2D complete)
- compiled deployment contract baseline (Phase 2D complete: release artifacts, migrate, health, rollback)
- performance gap closure (Phase 2C/2D complete: stage coverage, runtime toggles, mandatory `make check` perf gate)

Phase 3 is focused on platform maturity:
- observability and plugin/lifecycle extension system (Phase 3A complete)
- API-contract/auth ergonomics for API-first apps (schema contracts + OpenAPI/docs + auth scopes, Phase 3A complete)
- OpenAPI docs UX parity hardening (FastAPI-style interactive API browser, Phase 3B complete)
- OpenAPI docs polish via self-hosted Swagger UI option (Phase 3C complete)
- optional SQL builder and optional GDL2 adapter path (Phase 3B complete baseline)
- optional DisplayGroup/page-state compatibility helpers for migration paths (Phase 3B complete baseline)
- GNUstepWeb migration compatibility track (opt-in bridge, docs, sample migrations)
- release/distribution and documentation maturity (Phase 3C complete baseline)
- advanced performance trend analysis and expanded workload profiles (Phase 3C complete baseline)
- deferred parity capabilities baseline (websocket/SSE/realtime/mounting, Phase 3D complete)
- deferred ecosystem services track (Phase 3E complete baseline)
- ecosystem services follow-on scaffolds (plugin presets + optional job worker runtime contract + concrete Redis cache and filesystem attachment adapters, Phase 3E follow-on complete)
- Phase 3F complete: DX + reliability hardening (`arlen doctor`, toolchain matrix, ALNPg diagnostics, API convenience helpers, static mount ergonomics, concrete jobs/mail adapters, worker supervision baseline)
- Phase 3G complete: SQL builder v2 capability expansion + standalone data-layer reuse packaging (`ArlenData`)
- Phase 3H complete: multi-node clustering/runtime primitives (`/clusterz`, cluster headers, propane cluster controls, and cluster-focused integration validation)
- Phase 4A complete: query IR + safety foundation for expression-capable SQL builder paths
- Phase 4B complete: SQL surface completion for advanced composition/locking/join/window/set clauses
- Phase 4C complete: typed schema codegen and generated table/column helper APIs
- Phase 4D complete: builder execution caching + prepared statement reuse policy + structured/redacted query diagnostics
- Phase 4E complete: SQL conformance matrix + property/long-run regression hardening + migration/deprecation policy finalization

## Planned Next Phases (Post-4E)

Phase 4 rollout is complete in `docs/PHASE4_ROADMAP.md`.

Phase 5 rollout is complete in `docs/PHASE5_ROADMAP.md`, including:

- reliability contract mapping for advertised behavior
- external regression intake (competitor test scenarios translated into Arlen-native contract coverage)
- multi-database routing/tooling maturity and SQL-first compile-time typed data contracts

Phase 7 execution/planning is defined in `docs/PHASE7_ROADMAP.md`, including:

- Phase 7A initial runtime hardening slice completed (`docs/PHASE7A_RUNTIME_HARDENING.md`):
  - websocket session backpressure safety boundary
  - deterministic overload diagnostics contract (`503` + `X-Arlen-Backpressure-Reason`)
- Phase 7B initial security-default slice completed (`docs/PHASE7B_SECURITY_DEFAULTS.md`):
  - security profile presets (`balanced`, `strict`, `edge`)
  - fail-fast startup diagnostics for security misconfiguration contracts
- Phase 7C initial observability/operability slice completed (`docs/PHASE7C_OBSERVABILITY_OPERABILITY.md`):
  - request trace/correlation propagation contracts (`X-Correlation-Id`, `X-Trace-Id`, `traceparent`)
  - deterministic JSON health/readiness signal payloads and strict readiness policy switch
  - deploy runbook operability validation script integration
- Phase 7D initial service-durability slice completed (`docs/PHASE7D_SERVICE_DURABILITY.md`):
  - jobs idempotency-key dedupe/release contracts for in-memory and file job adapters
  - cache conformance hardening for zero-TTL persistence and nil-removal semantics
  - retry policy wrappers for mail/attachment adapters with deterministic exhaustion diagnostics
- remaining 7A/7B/7C/7D follow-on and 7E-7H planning:
  - additional runtime hardening for `boomhauer`/`propane`
  - security defaults and policy contracts
  - deeper observability/operability maturity and coding-agent-first DX contracts
  - ecosystem service durability, frontend integration starters, and distributed-runtime depth

Scope guardrails remain unchanged:
- admin/backoffice and full account-product surfaces remain outside Arlen core and are expected to ship as optional modules/products.
- full ORM as default layer remains "Maybe Someday", not a Phase 5 default requirement.

Maybe Someday backlog:
- LiveView-like server-driven UI
- full ORM as default framework layer

## Data Layer Direction

- Raw SQL remains first-class in Arlen.
- SQL abstraction is additive and optional.
- GDL2 is scoped as a compatibility adapter path, not a core dependency.

## Parity Direction

- Arlen parity targets behavior/capability outcomes for in-scope features.
- Arlen remains Cocoa-forward and GNUstep-native in API design.
- Syntax-level mirroring with Mojolicious is optional and only used when it improves clarity.
