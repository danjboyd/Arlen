# Arlen Phase 2 + Phase 3 Roadmap Index

Status: Active (Phase 2A-2D complete; Phase 3A-3E complete)  
Last updated: 2026-02-20

This index points to the current roadmap documents:

- `docs/PHASE2_ROADMAP.md`
- `docs/PHASE3_ROADMAP.md`
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
- ecosystem services follow-on scaffolds (plugin presets + optional job worker runtime contract + concrete Redis cache adapter, Phase 3E follow-on complete)

## Data Layer Direction

- Raw SQL remains first-class in Arlen.
- SQL abstraction is additive and optional.
- GDL2 is scoped as a compatibility adapter path, not a core dependency.

## Parity Direction

- Arlen parity targets behavior/capability outcomes for in-scope features.
- Arlen remains Cocoa-forward and GNUstep-native in API design.
- Syntax-level mirroring with Mojolicious is optional and only used when it improves clarity.
