# Arlen Phase 3 Roadmap

Status: Proposed with parity baseline  
Last updated: 2026-02-19

Related docs:
- `docs/PHASE2_ROADMAP.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/DEPLOYMENT.md`

## 1. Objective

Scale Arlen from "first production-ready" to a mature platform with strong observability, extensibility, and deliberate delivery of deferred parity capabilities.

## 2. Scope Summary

1. Observability and telemetry maturity.
2. Plugin/extension system and lifecycle hooks.
3. Data/model layer expansion (including optional SQL builder and optional GDL2 adapter).
4. Distribution and operations maturity for compiled deployments.
5. Deferred parity capabilities (realtime, mounting, ecosystem services).
6. Packaging, versioning, and onboarding maturity.
7. Advanced performance observability and tuning on top of Phase 2 mandatory perf gates.

## 3. Milestones

## 3.1 Phase 3A: Observability + Extensibility + API Contracts

Deliverables:
- Metrics endpoint and standardized runtime counters.
- Optional trace export integration (OpenTelemetry-friendly).
- Stable plugin API for middleware/helpers/lifecycle hooks.
- Explicit startup/shutdown dependency lifecycle contracts.
- Plugin loading/scaffolding through `arlen` CLI.
- OpenAPI generation for API-focused applications.

Acceptance:
- Metrics and key counters verified in integration tests.
- Example plugins pass compatibility tests.
- Lifecycle hook contract tests pass.
- OpenAPI snapshot tests pass for representative apps.

## 3.2 Phase 3B: Data Layer Maturation

Deliverables:
- Optional SQL builder (`ALNSQLBuilder`) for common CRUD/filter patterns.
- Keep raw SQL APIs first-class and always available.
- Productize PostgreSQL contract into an adapter model.
- Promote GDL2 from spike to optional adapter if Phase 2 spike is favorable.
- Add adapter conformance harness shared by all data adapters.

GDL2 decision criteria:
- No unacceptable performance overhead for common queries.
- Transaction semantics align with Arlen contract.
- Error propagation remains predictable and debuggable.

Acceptance:
- SQL builder coverage tests and generated SQL snapshots.
- Adapter conformance test harness across `ALNPg` and GDL2 adapter.

## 3.3 Phase 3C: Distribution, Release Management, and Documentation Maturity

Deliverables:
- Release artifact tooling and lifecycle documentation.
- First-class deployment runbooks for container and VM/systemd targets.
- CI performance gates with trend tracking and scenario expansion.
- Preserve Phase 2 mandatory perf gate while adding trend and drift analysis:
  - endpoint-level latency trend tracking (`p50`/`p95`/`p99`)
  - throughput and memory trend tracking
  - workload profile expansion for middleware-heavy and template-heavy scenarios
- Semantic versioning policy and deprecation lifecycle.
- Packaging/distribution docs and compatibility matrix.
- End-to-end cookbook sample apps and validated docs.

Acceptance:
- Performance regression thresholds enforced in CI.
- Trend reports are generated and archived per release cycle.
- Expanded scenario suite is stable enough for routine CI execution without noisy flake rates.
- Release checklist and migration guidance published.
- Deployment runbooks validated by automated smoke checks.
- Docs runnable and validated in CI.

## 3.4 Phase 3D: Deferred Parity Features (Realtime + Composition)

Deliverables:
- WebSocket support for app and controller workflows.
- Server-Sent Events support.
- App mounting/embedding composition model.
- Realtime channels/pubsub abstraction layered on websocket foundation.

Acceptance:
- Websocket and SSE integration tests pass under concurrent load.
- Mounting/embedding contract tests pass.
- Realtime channel behavior is covered with deterministic fixture tests.

## 3.5 Phase 3E: Ecosystem Services (Deferred Candidate Track)

Deliverables:
- Plugin-first background jobs abstraction.
- Caching abstraction with backend adapters.
- I18n localization framework.
- Optional mail and attachment abstractions.

Acceptance:
- Service contracts validated through plugin compatibility suites.
- Baseline guides and examples published for each adopted service area.

## 4. Principles

1. Keep GNUstep/Foundation-first design.
2. Prefer behavior parity over syntax mimicry.
3. Avoid heavy abstractions as defaults.
4. Prefer optional layers over mandatory complexity.
5. Preserve default-first developer ergonomics.

## 5. SQL and ORM Positioning in Phase 3

- `ALNPg` remains the default and most direct path.
- `ALNSQLBuilder` is optional convenience, not required runtime coupling.
- A full ORM should be considered only if it materially improves ergonomics without violating performance and simplicity goals.
- GDL2 support is optional and adapter-based, not a core dependency.

## 6. Parity Governance in Phase 3

- Continue quarterly Mojolicious parity deltas against the frozen baseline model in `docs/FEATURE_PARITY_MATRIX.md`.
- Every newly in-scope capability must include acceptance tests and migration notes when API behavior changes.
- Deferred items remain deferred until their prerequisites (observability, deployment reliability, and extension contracts) are complete.
