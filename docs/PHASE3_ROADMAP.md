# Arlen Phase 3 Roadmap

Status: Active (Phase 3A-3F complete; Phase 3G planned)  
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
- Added post-completion follow-on scaffolds:
  - `arlen generate plugin --preset` templates for Redis cache, queue-backed jobs, and SMTP mail flows
  - optional job worker runtime contract (`ALNJobWorkerRuntime`, `ALNJobWorker`, `ALNJobWorkerRunSummary`)
  - concrete Redis cache adapter (`ALNRedisCacheAdapter`) validated via cache conformance suite
  - concrete filesystem attachment adapter (`ALNFileSystemAttachmentAdapter`) validated via attachment conformance suite

Deliverables:
- Plugin-first background jobs abstraction.
- Caching abstraction with backend adapters.
- I18n localization framework.
- Optional mail and attachment abstractions.

Acceptance:
- Service contracts validated through plugin compatibility suites.
- Baseline guides and examples published for each adopted service area.

## 3.6 Phase 3F: DX + Reliability Hardening

Status: Complete (2026-02-20)

Completion highlights:
- Added bootstrap-first doctor workflow:
  - `bin/arlen doctor` delegates to `bin/arlen-doctor` before any `make arlen`
  - script-mode diagnostics run even when GNUstep or build prerequisites are missing
  - JSON output supports automation/CI consumers
- Published known-good onboarding baseline matrix in `docs/TOOLCHAIN_MATRIX.md`.
- Hardened `ALNPg` diagnostics and reliability:
  - regression coverage for direct and prepared parameterized `SELECT`
  - SQLSTATE + server diagnostics metadata in `NSError.userInfo`
- Added API convenience primitives:
  - typed query/header parsing helpers on `ALNContext`/`ALNController`
  - ETag/`304 Not Modified` helper contract
  - opt-in response envelope middleware (`apiHelpers.responseEnvelopeEnabled`)
  - controller envelope helper APIs
- Added static mount ergonomics:
  - explicit `mountStaticDirectory:atPrefix:allowExtensions:`
  - config-driven `staticMounts` loading
  - allowlist-driven static extension serving
  - canonical index redirects for directory and `/index.html` forms
- Completed remaining ecosystem runtime slice:
  - concrete filesystem jobs/mail adapters (`ALNFileJobAdapter`, `ALNFileMailAdapter`)
  - propane async worker supervision baseline (`jobWorker*` propane accessories + CLI/env overrides)
- Added Phase 3F unit/integration acceptance coverage for API helpers, static-mount semantics, and async worker supervision.

Deliverables:
- Toolchain onboarding hardening:
  - `arlen doctor` command for local environment checks
  - known-good toolchain/version compatibility matrix in docs
- PostgreSQL adapter reliability and diagnostics hardening:
  - parameterized `SELECT` behavior regression coverage
  - richer SQL diagnostics in `NSError` metadata (including SQLSTATE and server detail fields)
- API convenience primitives (opt-in only):
  - ETag / `304 Not Modified` helper contract
  - typed query/header parsing helpers
  - response envelope normalization helper/middleware
- Static mount ergonomics:
  - explicit static mount registration contract
  - canonical directory index redirect behavior
  - allowlist-based static serving contract
- Complete remaining Phase 3E follow-on runtime slice:
  - concrete jobs and mail backend adapters
  - propane-integrated worker supervision baseline for async job runtimes

Acceptance:
- `arlen doctor` validates representative supported environments and emits actionable diagnostics.
- ALNPg diagnostics include SQLSTATE-oriented metadata for representative failure modes.
- API convenience helpers are covered by positive/rejection tests and remain opt-in.
- Static mount behavior is integration-tested for allowlist and redirect semantics.
- Concrete jobs/mail adapters pass compatibility suites; worker supervision behavior passes integration tests.

## 3.7 Phase 3G: SQL Builder v2 + Data Layer Reuse (Planned)

Status: Planned

Deliverables:
- `ALNSQLBuilder` v2 capability expansion toward SQL::Abstract-family parity goals, while preserving Objective-C-native APIs.
- Core SQL builder expansions (non-dialect-specific):
  - nested boolean condition groups
  - broader operator coverage
  - joins/aliases/grouping/having
  - subquery and CTE composition
  - `RETURNING` and other commonly used ANSI/PostgreSQL-compatible clauses where practical
- Dialect extension layering for PostgreSQL-specific features (for example conflict/upsert-focused constructs) without forcing those semantics into baseline builder contracts.
- Publish reusable data-layer packaging for non-Arlen consumers (`ArlenData` module/targets) so SQL builder and adapter contracts can be consumed independently of HTTP/MVC runtime layers.
- Distribution guidance for partial source consumption and optional split-repo publishing workflow.

Acceptance:
- New SQL builder capabilities have deterministic SQL/parameter snapshot coverage.
- Dialect-specific features are isolated behind explicit APIs/modules.
- Non-Arlen sample usage is documented and validated in CI.
- Packaging/versioning policy for data-layer reuse is documented and enforceable.

## 3.8 Core Scope Decisions (Agreed)

- Keep Django-style admin/backoffice capabilities out of Arlen core; pursue optional separate product/module paths.
- Keep full account-management product surfaces (registration/reset/provider workflows) out of Arlen core; retain auth primitives in core.
- Treat ecosystem package volume as a platform/community outcome, not a core roadmap deliverable.
- Keep asset pipeline bundling out of core runtime scope; maintain official frontend integration guidance/starter paths without bundler lock-in.

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
