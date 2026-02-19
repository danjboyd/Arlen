# Arlen Phase 2 + Phase 3 Roadmap Index

Status: Active (Phase 2A and Phase 2B complete)  
Last updated: 2026-02-18

This index points to the current roadmap documents:

- `docs/PHASE2_ROADMAP.md`
- `docs/PHASE3_ROADMAP.md`

## Summary

Phase 2 is focused on adoption-critical capabilities:
- `propane` and production runtime hardening (Phase 2A complete)
- data/security core (Phase 2B complete)
- HTTP completeness
- PostgreSQL-first data layer (`ALNPg`)
- sessions/auth/security baseline
- developer error and validation ergonomics

Phase 3 is focused on platform maturity:
- observability and plugin system
- optional SQL builder and optional GDL2 adapter path
- advanced performance tuning
- packaging/versioning/docs maturity

## Data Layer Direction

- Raw SQL remains first-class in Arlen.
- SQL abstraction is additive and optional.
- GDL2 is scoped as a compatibility adapter path, not a core dependency (targeted for Phase 3 feasibility work).
