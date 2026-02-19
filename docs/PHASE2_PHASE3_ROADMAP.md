# Arlen Phase 2 + Phase 3 Roadmap Index

Status: Active (Phase 2A-2D complete; Phase 3 next)  
Last updated: 2026-02-19

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
- observability and plugin/lifecycle extension system
- optional SQL builder and optional GDL2 adapter path
- release/distribution and documentation maturity
- advanced performance trend analysis and expanded workload profiles
- deferred parity capabilities (websocket/SSE/realtime/mounting)
- deferred ecosystem services track

## Data Layer Direction

- Raw SQL remains first-class in Arlen.
- SQL abstraction is additive and optional.
- GDL2 is scoped as a compatibility adapter path, not a core dependency.

## Parity Direction

- Arlen parity targets behavior/capability outcomes for in-scope features.
- Arlen remains Cocoa-forward and GNUstep-native in API design.
- Syntax-level mirroring with Mojolicious is optional and only used when it improves clarity.
