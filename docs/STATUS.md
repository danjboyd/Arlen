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
- PostgreSQL-backed tests remain gated by `ARLEN_PG_TEST_DSN`.

## Next Session Focus

1. Phase 3G.1: expand `ALNSQLBuilder` capability surface toward SQL::Abstract-family parity goals.
2. Phase 3G.2: define PostgreSQL dialect-extension APIs and coverage boundaries.
3. Phase 3G.3: deliver standalone data-layer reuse packaging (`ArlenData`) and distribution guidance.

## Planned Phase Mapping (Post-3F)

- Phase 3F (complete):
  - onboarding and diagnostics (`arlen doctor`, compatibility matrix)
  - ALNPg reliability and SQL diagnostics hardening
  - optional API convenience helpers (ETag/304, typed query/header parsing, envelope normalization)
  - static mount allowlist/index ergonomics
  - remaining ecosystem runtime follow-on (jobs/mail adapters + worker supervision baseline)
- Phase 3G (planned):
  - `ALNSQLBuilder` v2 capability expansion toward SQL::Abstract-family parity goals (Objective-C-native API design)
  - PostgreSQL dialect-extension layer for PG-specific builder features
  - standalone data-layer packaging/reuse path (`ArlenData`) for non-Arlen applications
- Out of scope for Arlen core (explicitly documented):
  - Django-style admin/backoffice product
  - full account-management product surfaces
  - package-volume ecosystem targets as a core roadmap deliverable
