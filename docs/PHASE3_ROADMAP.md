# Arlen Phase 3 Roadmap

Status: Proposed  
Last updated: 2026-02-18

Related docs:
- `docs/PHASE2_ROADMAP.md`

## 1. Objective

Scale Arlen from "first production-ready" to a mature platform with stronger ecosystem, observability, and extensibility.

## 2. Scope Summary

1. Observability and telemetry maturity.
2. Plugin and extension system.
3. Data/model layer expansion (including optional SQL builder and GDL2 integration).
4. Advanced performance optimization and regression gates.
5. Packaging, versioning, and onboarding maturity.

## 3. Milestones

## 3.1 Phase 3A: Observability + Extensibility

Deliverables:
- Metrics endpoint and standardized runtime counters.
- Optional trace export integration (OpenTelemetry-friendly).
- Stable plugin API for middleware/helpers/lifecycle hooks.
- Plugin loading/scaffolding through `arlen` CLI.

Acceptance:
- Metrics and key counters verified in integration tests.
- Example plugins pass compatibility tests.

## 3.2 Phase 3B: Data Layer Maturation

Deliverables:
- Optional SQL builder (`ALNSQLBuilder`) for common CRUD/filter patterns.
- Keep raw SQL APIs first-class and always available.
- Productize PostgreSQL contract into an adapter model.
- Promote GDL2 from spike to optional adapter if Phase 2 spike is favorable.

GDL2 decision criteria:
- No unacceptable performance overhead for common queries.
- Transaction semantics align with Arlen contract.
- Error propagation remains predictable and debuggable.

Acceptance:
- SQL builder coverage tests and generated SQL snapshots.
- Adapter conformance test harness across `ALNPg` and GDL2 adapter.

## 3.3 Phase 3C: Performance + Distribution + Docs

Deliverables:
- Profile-driven optimization passes (router, parsing, rendering, db path).
- CI performance gates with trend tracking.
- Semantic versioning policy and deprecation lifecycle.
- Packaging/distribution docs and compatibility matrix.
- End-to-end cookbook sample apps and validated docs.

Acceptance:
- Performance regression thresholds enforced in CI.
- Release checklist and migration guidance published.
- Docs runnable and validated in CI.

## 4. Principles

1. Keep GNUstep/Foundation-first design.
2. Avoid heavy abstractions as defaults.
3. Prefer optional layers over mandatory complexity.
4. Preserve default-first developer ergonomics.

## 5. SQL and ORM Positioning in Phase 3

- `ALNPg` remains the default and most direct path.
- `ALNSQLBuilder` is optional convenience, not required runtime coupling.
- A full ORM should be considered only if it materially improves ergonomics without violating performance and simplicity goals.
- GDL2 support is optional and adapter-based, not a core dependency.
