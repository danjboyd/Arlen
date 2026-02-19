# Arlen Phase 2 + Phase 3 Roadmap Index

Status: Active (Phase 2A, Phase 2B, and Phase 2C complete; Phase 2D next)  
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
- parity baseline completion for remaining in-scope core capabilities (Phase 2D)
- compiled deployment contract baseline (release artifacts, migrate, health, rollback)
- performance gap closure (stage coverage, runtime toggles, mandatory CI perf gate)

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
