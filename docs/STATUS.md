# Arlen Status Checkpoint

Last updated: 2026-02-20

## Current Milestone State

- Phase 1: complete
- Phase 2A: complete
- Phase 2B: complete
- Phase 2C: complete (2026-02-19)
- Phase 2D: complete (2026-02-19)
- Phase 3A: complete (2026-02-19)
- Phase 3B: complete (2026-02-19)
- Phase 3C: complete (2026-02-20)
- Phase 3D: complete (2026-02-20)
- Phase 3E: complete (2026-02-20)
- Phase 3F: complete (2026-02-20)
- Phase 3G: complete (2026-02-20)
- Phase 3H: complete (2026-02-20)
- Phase 4A: complete (2026-02-20)
- Phase 4B: complete (2026-02-20)
- Phase 4C: complete (2026-02-20)
- Phase 4D: complete (2026-02-20)

## Completed Today (2026-02-20)

- Completed Phase 3C release/distribution/documentation tranche.
- Added profile-based perf expansion and trend reporting:
  - profile pack in `tests/performance/profiles/`
  - per-profile policy/baseline support
  - trend outputs (`latest_trend.json`, `latest_trend.md`)
  - archived run history under `build/perf/history/<profile>/`
- Added CI quality gate entrypoints:
  - `tools/ci/run_phase3c_quality.sh`
  - `.github/workflows/phase3c-quality.yml`
  - `make ci-quality`
- Added OpenAPI docs style option `swagger`:
  - config acceptance for `openapi.docsUIStyle = "swagger"`
  - runtime endpoint `/openapi/swagger`
  - unit/integration coverage for swagger docs rendering
- Added deployment runbook smoke automation:
  - `tools/deploy/smoke_release.sh`
  - `make deploy-smoke`
  - deployment integration coverage for smoke workflow
- Added migration readiness package:
  - guide: `docs/MIGRATION_GSWEB.md`
  - side-by-side sample app: `examples/gsweb_migration`
  - API-first reference app: `examples/api_reference`
  - perf profile coverage for both reference and migration workloads
- Added Phase 3C documentation set:
  - `docs/RELEASE_PROCESS.md`
  - `docs/PERFORMANCE_PROFILES.md`
  - updated `README.md`, `docs/README.md`, `docs/GETTING_STARTED.md`, `docs/CLI_REFERENCE.md`, `docs/DEPLOYMENT.md`, `docs/PHASE3_ROADMAP.md`
- Completed Phase 3D realtime/composition tranche:
  - websocket upgrade + frame handling in `ALNHTTPServer`
  - controller-level realtime helpers (`acceptWebSocketEcho`, `acceptWebSocketChannel`, `renderSSEEvents`)
  - mount/embedding contract via `mountApplication:atPrefix:`
  - realtime channel/pubsub abstraction via `ALNRealtimeHub`
  - boomhauer routes for websocket echo/channel, SSE ticker, and mounted app sample routes
  - unit/integration coverage for realtime and mount composition flows
- Completed Phase 3E ecosystem services tranche:
  - service adapter contracts (`ALNJobAdapter`, `ALNCacheAdapter`, `ALNLocalizationAdapter`, `ALNMailAdapter`, `ALNAttachmentAdapter`)
  - in-memory baseline adapters and compatibility suites (`ALNRun*ConformanceSuite`, `ALNRunServiceCompatibilitySuite`)
  - plugin-first service override wiring through `ALNApplication`
  - controller/context service access helpers and i18n locale fallback config
  - boomhauer sample service routes (`/services/cache`, `/services/jobs`, `/services/i18n`, `/services/mail`, `/services/attachments`)
  - published guide: `docs/ECOSYSTEM_SERVICES.md`
- Completed Phase 3E follow-on execution slice:
  - added `arlen generate plugin --preset` templates for Redis cache, queue-backed jobs, and SMTP mail workflows
  - defined optional worker runtime contract (`ALNJobWorkerRuntime`, `ALNJobWorker`, `ALNJobWorkerRunSummary`)
  - implemented concrete Redis cache backend adapter (`ALNRedisCacheAdapter`) with conformance-compatible behavior
  - implemented concrete filesystem attachment backend adapter (`ALNFileSystemAttachmentAdapter`)
  - added production guidance for service persistence + retention policy baselines
  - added integration coverage for plugin preset generation and unit coverage for worker drain/ack/retry/run-limit + Redis cache/attachment adapter conformance
- Completed Phase 3F DX + reliability hardening tranche:
  - added bootstrap-first doctor path (`bin/arlen doctor` -> `bin/arlen-doctor`) with JSON diagnostics output
  - published known-good toolchain matrix (`docs/TOOLCHAIN_MATRIX.md`)
  - hardened ALNPg diagnostics with SQLSTATE/server metadata and parameterized `SELECT` regression coverage
  - added API convenience primitives (typed query/header parsing, ETag/304 helpers, response-envelope helpers/middleware)
  - implemented static mount ergonomics (explicit mounts, allowlist serving, canonical index redirects)
  - completed concrete jobs/mail file adapters and propane async worker supervision baseline
  - expanded unit/integration acceptance coverage for all new 3F behavior slices
- Completed Phase 3G SQL builder and data-layer reuse tranche:
  - expanded `ALNSQLBuilder` to v2 query surface (nested boolean groups, expanded predicates, joins/aliases, grouping/having, CTE/subquery composition, and `RETURNING`)
  - added advanced expression/query composition APIs:
    - select expressions with aliases and placeholder-safe parameter shifting
    - expression-aware ordering (`NULLS FIRST/LAST`, parameterized order expressions)
    - subquery and lateral join composition
    - tuple/composite cursor predicate support via expression predicates
  - added explicit PostgreSQL dialect extension builder (`ALNPostgresSQLBuilder`) for `ON CONFLICT` upsert semantics
  - extended PostgreSQL conflict/upsert APIs with expression-based `DO UPDATE SET` assignments and optional `DO UPDATE ... WHERE` clauses
  - published standalone data-layer packaging via `src/ArlenData/ArlenData.h`
  - added non-Arlen validation path (`examples/arlen_data`, `make test-data-layer`)
  - wired standalone data-layer validation into CI quality gate (`tools/ci/run_phase3c_quality.sh`)
  - published distribution and versioning guidance in `docs/ARLEN_DATA.md`
- Completed Phase 3H multi-node clustering/distributed-runtime tranche:
  - added cluster config contract defaults/env overrides (`cluster.*`, `ARLEN_CLUSTER_*`)
  - added built-in cluster status endpoint (`/clusterz`)
  - added cluster identity response headers (`X-Arlen-Cluster`, `X-Arlen-Node`, `X-Arlen-Worker-Pid`)
  - added propane cluster CLI/env controls and worker export wiring
  - added unit/integration validation for cluster config/runtime/propane propagation
- Completed Phase 4A query-IR and safety-foundation tranche:
  - added internal trusted-expression IR representation for expression-capable builder clauses
  - added source-compatible identifier-binding expression APIs (`{{token}}`) for select/where/having/order/join-on composition
  - enforced deterministic malformed-shape diagnostics for expression IR, parameter arrays, and identifier-binding contracts
  - added strict placeholder/parameter coverage checks for expression templates
  - added regression suites:
    - `tests/unit/Phase4ATests.m` (snapshot + negative/safety validation)
    - `tests/unit/PgTests.m` identifier-template PostgreSQL execution coverage
- Completed Phase 4D performance and diagnostics tranche:
  - added builder-driven execution APIs in `ALNPgConnection`/`ALNPg` (`executeBuilderQuery`, `executeBuilderCommand`)
  - added builder compilation cache and prepared-statement reuse policy controls (`disabled`/`auto`/`always`)
  - added structured query diagnostics listener pipeline with stage events (`compile`, `execute`, `result`, `error`)
  - added redaction-safe query metadata defaults (`sql` omitted unless explicitly enabled) and optional stderr event emission
  - added runtime cache controls (`preparedStatementCacheLimit`, `builderCompilationCacheLimit`, `resetExecutionCaches`)
  - added PostgreSQL regression coverage for cache-hit behavior and diagnostics metadata contracts

## Verification State (2026-02-20)

- `make test-unit`: passing
- `make test-integration`: passing
- profile perf checks executed:
  - `default`
  - `middleware_heavy`
  - `template_heavy`
  - `api_reference`
  - `migration_sample`
- New Phase 3D checks executed:
  - websocket echo round-trip integration test
  - websocket channel fanout integration test
  - concurrent SSE integration test
  - mounted app composition unit/integration tests
- New Phase 3E checks executed:
  - plugin-driven service wiring + lifecycle verification
  - service compatibility suite coverage for jobs/cache/i18n/mail/attachments
  - controller-level service helper route verification
  - boomhauer integration tests for service sample routes
- New Phase 3F checks executed:
  - `arlen doctor` bootstrap pre-build diagnostics + JSON payload validation
  - ALNPg SQLSTATE/diagnostics regression tests
  - API helper tests (typed query/header parsing, ETag/304, envelope helper + opt-in middleware behavior)
  - static serving integration tests for canonical index redirects and extension allowlist enforcement
  - propane integration test for supervised async worker spawn + respawn behavior
- New Phase 3G checks executed:
  - deterministic SQL snapshot coverage for builder v2 behavior (`tests/unit/Phase3GTests.m`)
  - PostgreSQL conflict/upsert dialect-extension snapshot coverage
  - standalone non-Arlen data-layer build/run validation (`make test-data-layer`)
- New Phase 3H checks executed:
  - cluster config default/override regression coverage (`tests/unit/ConfigTests.m`)
  - `/clusterz` built-in endpoint and cluster response header integration coverage
  - propane cluster override propagation integration coverage
- New Phase 4A checks executed:
  - `tests/unit/Phase4ATests.m` passing (expression IR snapshot, malformed contract rejection, and safety paths)
  - PostgreSQL expression-template execution regression passing (`testSQLBuilderExpressionTemplatesWithIdentifierBindingsExecuteAgainstPostgres`)
- New Phase 4B checks executed:
  - deterministic snapshot coverage for set operations, windows, predicates, joins, CTE columns, and locking (`tests/unit/Phase4BTests.m`)
  - PostgreSQL execution regression for 4B clause families (`testSQLBuilderPhase4BFeaturesExecuteAgainstPostgres`)
  - misuse-path diagnostics for invalid set-operation and locking contracts
- New Phase 4C checks executed:
  - deterministic schema artifact renderer coverage (`tests/unit/SchemaCodegenTests.m`)
  - CLI schema codegen integration and generated-helper compile/execute smoke (`testArlenSchemaCodegenGeneratesTypedHelpers`)
  - `arlen schema-codegen` overwrite and manifest contract coverage
- New Phase 4D checks executed:
  - structured builder diagnostics/caching regression (`testBuilderExecutionEmitsStructuredEventsAndUsesCaches`)
  - redaction + SQLSTATE diagnostics regression (`testBuilderExecutionErrorEventsIncludeSQLStateAndStayRedactedByDefault`)
  - full suite verification after toolchain link update (`make test-unit`, `make test-integration`, `make test-data-layer`)
- PostgreSQL-backed tests remain gated by `ARLEN_PG_TEST_DSN`.

## Next Session Focus

1. Execute Phase 4E conformance + migration hardening tranche from `docs/PHASE4_ROADMAP.md`.
2. Add property/fuzz coverage for placeholder shifting, parameter ordering, tuple predicates, and expression nesting.
3. Publish and validate migration guidance from v2 string-heavy builder usage to IR/typed patterns.

## Planned Phase Mapping (Post-4C)

- Phase 3F (complete):
  - onboarding and diagnostics (`arlen doctor`, compatibility matrix)
  - ALNPg reliability and SQL diagnostics hardening
  - optional API convenience helpers (ETag/304, typed query/header parsing, envelope normalization)
  - static mount allowlist/index ergonomics
  - remaining ecosystem runtime follow-on (jobs/mail adapters + worker supervision baseline)
- Phase 3G (complete):
  - `ALNSQLBuilder` v2 capability expansion toward SQL::Abstract-family parity goals (Objective-C-native API design)
  - PostgreSQL dialect-extension layer for PG-specific builder features (`ALNPostgresSQLBuilder`)
  - standalone data-layer packaging/reuse path (`ArlenData`) for non-Arlen applications + CI validation
- Phase 3H (complete):
  - multi-node clustering primitives and distributed runtime hardening
  - cluster-oriented integration validation + operational contracts
- Maybe Someday backlog:
  - LiveView-like server-driven UI
  - full ORM as default framework layer
- Post-4C planned:
  - Phase 4E: conformance + migration hardening
  - official frontend toolchain integration guides/starters
- Completed in Phase 4:
  - Phase 4A: query IR + safety foundation
  - Phase 4B: SQL surface completion
  - Phase 4C: typed ergonomics + schema codegen
  - Phase 4D: performance + diagnostics hardening
- Out of scope for Arlen core (explicitly documented):
  - Django-style admin/backoffice product
  - full account-management product surfaces
  - package-volume ecosystem targets as a core roadmap deliverable
