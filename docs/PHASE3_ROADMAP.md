# Arlen Phase 3 Roadmap

Status: Complete (Phase 3A-3E complete)  
Last updated: 2026-02-20

Related docs:
- `docs/PHASE2_ROADMAP.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/DEPLOYMENT.md`

## 1. Objective

Scale Arlen from "first production-ready" to a mature platform with strong observability, extensibility, API-contract ergonomics, and deliberate delivery of deferred parity capabilities while preserving Arlen-native design defaults.

## 2. Scope Summary

1. Observability and telemetry maturity.
2. API-contract and auth ergonomics for API-first applications.
3. Plugin/extension system and lifecycle hooks.
4. Data/model layer expansion (including optional SQL builder and optional GDL2 adapter).
5. GNUstepWeb migration compatibility track (additive and opt-in).
6. Distribution and operations maturity for compiled deployments.
7. Deferred parity capabilities (realtime, mounting, ecosystem services).
8. Packaging, versioning, and onboarding maturity.
9. Advanced performance observability and tuning on top of Phase 2 mandatory perf gates.

## 3. Milestones

## 3.1 Phase 3A: Observability + API Contracts + Extensibility

Deliverables:
- Metrics endpoint and standardized runtime counters.
- Optional trace export integration (OpenTelemetry-friendly).
- Objective-C-first request/response schema contracts for validation and OpenAPI emission.
- OpenAPI generation for API-focused applications.
- Built-in API documentation UI path (OpenAPI viewer) for local/dev use.
- SDK/export hooks from generated OpenAPI artifacts.
- First-party auth baseline for API workloads:
  - bearer/JWT verification helpers
  - OAuth2 scope checks
  - route-level RBAC/policy helpers
- Stable plugin API for middleware/helpers/lifecycle hooks.
- Explicit startup/shutdown dependency lifecycle contracts.
- Plugin loading/scaffolding through `arlen` CLI.

Acceptance:
- Metrics and key counters verified in integration tests.
- Schema-contract validation and coercion behavior verified in unit/integration tests.
- OpenAPI snapshot tests pass for representative apps.
- API documentation UI endpoint serves generated specs for representative apps.
- Auth/scope/RBAC contract tests pass for positive and rejection paths.
- Example plugins pass compatibility tests.
- Lifecycle hook contract tests pass.

## 3.2 Phase 3B: Data Layer Maturation

Status: Complete (2026-02-19)

Deliverables:
- Optional SQL builder (`ALNSQLBuilder`) for common CRUD/filter patterns.
- Keep raw SQL APIs first-class and always available.
- Productize PostgreSQL contract into an adapter model.
- Promote GDL2 from spike to optional adapter with migration-oriented docs.
- Add optional data-controller helper (`ALNDisplayGroup`-style) for sort/filter/batch workflows on top of adapters.
- Add adapter conformance harness shared by all data adapters.
- Add session/page-state compatibility helper layer (opt-in) for migration scenarios that require it.
- Upgrade OpenAPI docs UI from baseline viewer to FastAPI-style interactive API docs (try-it-out workflow), while keeping the current lightweight viewer path available as fallback.

GDL2 decision criteria:
- No unacceptable performance overhead for common queries.
- Transaction semantics align with Arlen contract.
- Error propagation remains predictable and debuggable.

Acceptance:
- SQL builder coverage tests and generated SQL snapshots.
- Adapter conformance test harness across `ALNPg` and GDL2 adapter.
- Optional data-controller helper contract tests pass for sort/filter/batch behavior.
- Session/page-state compatibility helper tests pass without changing default Arlen stateless behavior.
- Interactive docs endpoint supports end-to-end request execution against representative API routes in integration tests.

## 3.3 Phase 3C: Distribution, Release Management, and Documentation Maturity

Status: Complete (2026-02-20)

Completion highlights:
- Profile-based perf expansion with trend archives (`tests/performance/profiles/*`, `build/perf/history/*`, `latest_trend.*`).
- CI quality workflow and multi-profile perf artifact publication (`.github/workflows/phase3c-quality.yml`).
- Self-hosted Swagger-style docs UI option (`openapi.docsUIStyle = "swagger"`, `/openapi/swagger`).
- Release lifecycle and semver/deprecation process docs (`docs/RELEASE_PROCESS.md`).
- Automated deployment runbook smoke validation (`tools/deploy/smoke_release.sh`, integration coverage).
- Migration readiness package:
  - GSWeb migration guide (`docs/MIGRATION_GSWEB.md`)
  - side-by-side migrated sample (`examples/gsweb_migration`)
  - API-first reference app (`examples/api_reference`)
  - benchmark profile pack entries for reference and migration workloads.

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
- OpenAPI docs polish tranche:
  - self-hosted Swagger UI wired to generated `/openapi.json`
  - configurable docs UI style selection without removing existing interactive/viewer fallbacks
- End-to-end cookbook sample apps and validated docs.
- Migration readiness package:
  - GSWeb-to-Arlen migration guide
  - migrated sample app demonstrating side-by-side equivalent behavior
  - API-first reference app demonstrating schema/OpenAPI/auth defaults
  - benchmark profile pack for API reference workloads

Acceptance:
- Performance regression thresholds enforced in CI.
- Trend reports are generated and archived per release cycle.
- Expanded scenario suite is stable enough for routine CI execution without noisy flake rates.
- Release checklist and migration guidance published.
- Deployment runbooks validated by automated smoke checks.
- Docs runnable and validated in CI.
- Swagger UI docs endpoint serves generated specs and supports representative try-it-out API execution in integration tests.
- Migration sample app and API reference app pass integration/perf baseline checks.

## 3.4 Phase 3D: Deferred Parity Features (Realtime + Composition)

Status: Complete (2026-02-20)

Completion highlights:
- WebSocket runtime support in `ALNHTTPServer` with controller-driven upgrade contracts.
- Controller helpers for realtime workflows:
  - `acceptWebSocketEcho`
  - `acceptWebSocketChannel:`
  - `renderSSEEvents:`
- Mount/embedding composition contract in `ALNApplication`:
  - `mountApplication:atPrefix:`
  - path rewriting and mounted app dispatch with prefix tracking header.
- Realtime channel/pubsub abstraction:
  - `ALNRealtimeHub`
  - deterministic fanout and unsubscribe behavior covered in unit tests.
- Integration validation:
  - websocket echo round-trip
  - websocket channel fanout between concurrent clients
  - SSE under concurrent request load
  - mounted app route composition behavior.

Deliverables:
- WebSocket support for app and controller workflows.
- Server-Sent Events support.
- App mounting/embedding composition model.
- Realtime channels/pubsub abstraction layered on websocket foundation.
- Promote any Phase 3A preview APIs to stable contracts only after compatibility/perf criteria are met.

Acceptance:
- Websocket and SSE integration tests pass under concurrent load.
- Mounting/embedding contract tests pass.
- Realtime channel behavior is covered with deterministic fixture tests.

## 3.5 Phase 3E: Ecosystem Services (Deferred Candidate Track)

Status: Complete (2026-02-20)

Completion highlights:
- Added ecosystem service contracts and in-memory baseline adapters:
  - jobs: `ALNJobAdapter`
  - cache: `ALNCacheAdapter`
  - i18n: `ALNLocalizationAdapter`
  - mail: `ALNMailAdapter`
  - attachments: `ALNAttachmentAdapter`
- Added compatibility suite APIs for plugin adapter verification:
  - `ALNRunJobAdapterConformanceSuite`
  - `ALNRunCacheAdapterConformanceSuite`
  - `ALNRunLocalizationAdapterConformanceSuite`
  - `ALNRunMailAdapterConformanceSuite`
  - `ALNRunAttachmentAdapterConformanceSuite`
  - `ALNRunServiceCompatibilitySuite`
- Added plugin-first service override hooks on `ALNApplication` and request/controller access via `ALNContext` + `ALNController`.
- Added Phase 3E unit/integration coverage, including boomhauer sample service routes.
- Published service guide and usage examples in `docs/ECOSYSTEM_SERVICES.md`.

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
6. Keep compatibility/migration surfaces additive and opt-in.
7. Keep Arlen-native APIs (`ALN*`) as canonical contracts.

## 5. SQL and ORM Positioning in Phase 3

- `ALNPg` remains the default and most direct path.
- `ALNSQLBuilder` is optional convenience, not required runtime coupling.
- A full ORM should be considered only if it materially improves ergonomics without violating performance and simplicity goals.
- GDL2 support is optional and adapter-based, not a core dependency.

## 6. Compatibility Guardrails

- GSWeb/WebObjects-inspired compatibility lives in explicit compatibility modules, not Arlen core defaults.
- App scaffolds and docs remain Arlen-native by default.
- Migration helpers must not require runtime-global behavior changes for non-migrating apps.
- New compatibility layers must pass the same perf/quality gates as core APIs.

## 7. Parity Governance in Phase 3

- Continue quarterly Mojolicious parity deltas against the frozen baseline model in `docs/FEATURE_PARITY_MATRIX.md`.
- Every newly in-scope capability must include acceptance tests and migration notes when API behavior changes.
- Deferred items remain deferred until their prerequisites (observability, deployment reliability, and extension contracts) are complete.
