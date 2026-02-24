# CLI Reference

This document describes currently implemented command-line interfaces.

## `arlen`

Usage:

```text
arlen <command> [options]
```

Commands:

### `arlen new <AppName> [--full|--lite] [--force] [--json]`

Create a new app scaffold.

- `--full`: full app scaffold (default)
- `--lite`: single-file lite scaffold
- `--force`: overwrite existing files where allowed
- `--json`: emit machine-readable scaffold payload (`phase7g-agent-dx-contracts-v1`)
- `--help` / `-h`: show command usage

### `arlen doctor [--env <name>] [--json]`

Run bootstrap environment diagnostics without requiring a framework build.

- delegated by `bin/arlen` directly to `bin/arlen-doctor` before any `make arlen`
- intended for first-run toolchain validation (GNUstep/tooling presence)
- `--env <name>`: include the target environment name in output (default `development`)
- `--json`: emit structured JSON diagnostics

### `arlen generate <controller|endpoint|model|migration|test|plugin|frontend> <Name> [options] [--json]`

Generate app artifacts.

Common generator options (`controller` and `endpoint`):

- `--route <path>`: wire route into `src/main.m` or `app_lite.m`
- `--method <HTTP>`: route method override (default `GET`)
- `--action <name>`: generated action method name (default `index`)
- `--template [<logical_template>]`: create template + render stub
- `--api`: generate JSON-oriented endpoint action

Plugin generator options:

- `--preset <generic|redis-cache|queue-jobs|smtp-mail>`: choose service-oriented plugin scaffold (default `generic`)

Frontend generator options:

- `--preset <vanilla-spa|progressive-mpa>`: choose frontend starter scaffold (default `vanilla-spa`)
- `--json`: emit machine-readable scaffold/fix-it payload (`phase7g-agent-dx-contracts-v1`)

Generator behavior:

- `controller`: `src/Controllers/<Name>Controller.{h,m}`
- `endpoint`: same controller output with endpoint-oriented defaults (`--route` required)
- `model`: `src/Models/<Name>Repository.{h,m}`
- `migration`: `db/migrations/<timestamp>_<name>.sql`
- `test`: `tests/<Name>Tests.m`
- `plugin`: `src/Plugins/<Name>Plugin.{h,m}` and class auto-registration in `config/app.plist` (`plugins.classes`), with optional `--preset` service templates
  - `redis-cache` preset uses `ALNRedisCacheAdapter` when `ARLEN_REDIS_URL` is configured
- `frontend`: deterministic starter assets under `public/frontend/<name_slug>/` with `index.html`, `app.js`, `styles.css`, `starter_manifest.json`, and `README.md`

Notes:

- placeholder routes are supported (for example `/user/admin/:id`)
- endpoint generator can create route + action + optional template in one command

### `arlen migrate [--env <name>] [--database <target>] [--dsn <connection_string>] [--dry-run]`

Apply SQL migrations from `db/migrations` to PostgreSQL.

- `--env <name>`: select runtime environment (default: `development`)
- `--database <target>`: select migration target (default: `default`)
- `--dsn <connection_string>`: override config DSN
- `--dry-run`: list pending migrations without applying
- per-target migration directory: `db/migrations/<target>` (for non-default targets)
- per-target migration state table: `arlen_schema_migrations__<target>`
- target-specific env override: `ARLEN_DATABASE_URL_<TARGET>`

### `arlen schema-codegen [--env <name>] [--database <target>] [--dsn <connection_string>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--typed-contracts] [--force]`

Introspect PostgreSQL schema metadata and generate typed table/column helper APIs.

- `--env <name>`: select runtime environment (default: `development`)
- `--database <target>`: select codegen target (default: `default`)
- `--dsn <connection_string>`: override config DSN
- `--output-dir <path>`: destination directory for generated Objective-C files (default: `src/Generated`)
- `--manifest <path>`: destination JSON manifest path (default: `db/schema/arlen_schema.json`)
- `--prefix <ClassPrefix>`: class prefix for generated APIs (default: `ALNDB`)
- `--typed-contracts`: include typed row/insert/update contracts and decode helpers in generated artifacts
- `--force`: overwrite existing generated files

For non-default targets when path/prefix options are omitted:

- output dir default: `src/Generated/<target>`
- manifest default: `db/schema/arlen_schema_<target>.json`
- class prefix default: `ALNDB<PascalTarget>`
- manifest includes `"database_target": "<target>"`

Generated artifacts:

- `<output-dir>/<prefix>Schema.h`
- `<output-dir>/<prefix>Schema.m`
- `<manifest>`

### `arlen typed-sql-codegen [--input-dir <path>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--force]`

Compile SQL files with metadata comments into typed parameter/result helpers.

- `--input-dir <path>`: SQL source directory (default: `db/sql/typed`)
- `--output-dir <path>`: generated Objective-C output directory (default: `src/Generated`)
- `--manifest <path>`: typed SQL manifest output (default: `db/schema/arlen_typed_sql.json`)
- `--prefix <ClassPrefix>`: generated class prefix (default: `ALNDB`)
- `--force`: overwrite existing generated files

### `arlen boomhauer [server args...]`

Build and run `boomhauer` for the current app root.

- delegates to framework `bin/boomhauer` with `ARLEN_APP_ROOT` + `ARLEN_FRAMEWORK_ROOT`
- defaults to watch mode (same as direct `bin/boomhauer`)
- transpile/compile failures in watch mode do not terminate supervisor; diagnostics are served until next successful rebuild
- server args are passed through (`--watch`, `--no-watch`, `--prepare-only`, `--port`, `--host`, `--env`, `--once`, `--print-routes`)

### `arlen propane [manager args...]`

Run production manager (`propane`) for the current app root.

- manager args are forwarded to `bin/propane`
- all production manager settings are called "propane accessories"

### `arlen routes`

Build app and print resolved routes (`--print-routes`).

### `arlen test [--unit|--integration|--all]`

Run framework tests.

- default: equivalent to `--all`

### `arlen perf`

Run performance suite and regression gate (`make perf`).

Profile selection is environment-driven:

- `ARLEN_PERF_PROFILE=default|middleware_heavy|template_heavy|api_reference|migration_sample`
- `ARLEN_PERF_PROFILE=default|middleware_heavy|template_heavy|api_reference|migration_sample|comparison_http`
- `ARLEN_PERF_CONCURRENCY=<n>` (optional concurrent request fanout per scenario)

### `arlen check [--dry-run] [--json]`

Run full quality gate (`make check`):

- unit tests
- integration tests
- perf gate
- `--dry-run`: emit planned `make check` workflow without executing it
- `--json`: emit machine-readable workflow payloads/failure diagnostics (`phase7g-agent-dx-contracts-v1`)

### `arlen build [--dry-run] [--json]`

Build framework targets (`make all`).

- `--dry-run`: emit planned `make all` workflow without executing it
- `--json`: emit machine-readable workflow payloads/failure diagnostics (`phase7g-agent-dx-contracts-v1`)

## `build/eocc`

Template transpiler used by `make`/`boomhauer` pipelines.

Usage:

```text
build/eocc --template-root <dir> --output-dir <dir> [--registry-out <file>] <template1.html.eoc> [template2 ...]
```

Diagnostics behavior:

- syntax/transpile failures return non-zero and emit deterministic location metadata:
  - `eocc: location path=<path> line=<line> column=<column>`
- lint warnings are emitted during successful transpile:
  - `eocc: warning path=<path> line=<line> column=<column> code=<code> message=<message>`
  - current lint code: `unguarded_include` (include return value should be checked)
- lint warnings are non-fatal in this phase slice
- sigil local grammar supports:
  - `$identifier`
  - `$identifier(.identifier)*` (dotted keypaths)

### `arlen config [--env <name>] [--json]`

Load and print merged runtime config.

- `--env <name>`: select environment overlay
- `--json`: pretty JSON output

## `boomhauer` Script (`bin/boomhauer`)

Usage:

```text
boomhauer [options]
```

Behavior:

- if run inside app root (`config/app.plist` plus `src/main.m` or `app_lite.m`), compiles and runs that app
- defaults to watch mode
- in app-root watch mode, build failures are captured and rendered as development diagnostics
- websocket session upgrades are bounded by `runtimeLimits.maxConcurrentWebSocketSessions` (default `256`)
- websocket backpressure limit violations return deterministic overload diagnostics:
  - status `503 Service Unavailable`
  - header `Retry-After: 1`
  - header `X-Arlen-Backpressure-Reason: websocket_session_limit`
- security misconfiguration now fails startup deterministically (for example missing `session.secret` when `session.enabled=YES`)
- route compile validation now fails startup deterministically when enabled (`routing.compileOnStart=YES`):
  - invalid action/guard signatures
  - invalid route schema transformer/type readiness
- request responses emit correlation/trace headers:
  - `X-Request-Id`
  - `X-Correlation-Id`
  - `X-Trace-Id` + `traceparent` (when trace propagation is enabled)
- built-in health/readiness probes support JSON signal payloads when requested:
  - `GET /healthz` with `Accept: application/json` (or `?format=json`)
  - `GET /readyz` with `Accept: application/json` (or `?format=json`)
  - strict readiness (`503 not_ready` before startup) can be enabled with `ARLEN_READINESS_REQUIRES_STARTUP=1`
  - quorum-gated readiness in cluster mode can be enabled with `ARLEN_READINESS_REQUIRES_CLUSTER_QUORUM=1`
- distributed runtime diagnostics include:
  - `GET /clusterz` quorum and coordination capability-matrix payload
  - response headers `X-Arlen-Cluster-Status`, `X-Arlen-Cluster-Observed-Nodes`, and `X-Arlen-Cluster-Expected-Nodes` (when `cluster.emitHeaders=YES`)
- built-in observability/API docs endpoints are available when enabled:
  - `/metrics`
  - `/clusterz`
  - `/openapi.json`
  - `/openapi` (interactive explorer by default)
  - `/openapi/viewer` (lightweight fallback viewer)
  - `/openapi/swagger` (self-hosted swagger-style docs UI)
- built-in Phase 3D sample realtime/composition routes:
  - `/ws/echo`
  - `/ws/channel/:channel`
  - `/sse/ticker`
  - mounted app sample at `/embedded/*`
- built-in Phase 3E sample ecosystem-service routes:
  - `/services/cache`
  - `/services/jobs`
  - `/services/i18n`
  - `/services/mail`
  - `/services/attachments`

Options:

- `--watch` (default)
- `--no-watch`
- `--once`
- `--prepare-only`
- `--help` / `-h`

Environment:

- `ARLEN_APP_ROOT`
- `ARLEN_FRAMEWORK_ROOT`
- `ARLEN_SECURITY_PROFILE` (`balanced`, `strict`, or `edge`; legacy `MOJOOBJC_SECURITY_PROFILE` also accepted)
- `ARLEN_MAX_WEBSOCKET_SESSIONS` (runtime websocket session limit; legacy `MOJOOBJC_MAX_WEBSOCKET_SESSIONS` also accepted)
- `ARLEN_TRACE_PROPAGATION_ENABLED` (default `1`; legacy `MOJOOBJC_TRACE_PROPAGATION_ENABLED` also accepted)
- `ARLEN_HEALTH_DETAILS_ENABLED` (default `1`; legacy `MOJOOBJC_HEALTH_DETAILS_ENABLED` also accepted)
- `ARLEN_READINESS_REQUIRES_STARTUP` (default `0`; legacy `MOJOOBJC_READINESS_REQUIRES_STARTUP` also accepted)
- `ARLEN_READINESS_REQUIRES_CLUSTER_QUORUM` (default `0`; legacy `MOJOOBJC_READINESS_REQUIRES_CLUSTER_QUORUM` also accepted)
- `ARLEN_CLUSTER_OBSERVED_NODES` (defaults to expected nodes; legacy `MOJOOBJC_CLUSTER_OBSERVED_NODES` also accepted)
- `ARLEN_ROUTING_COMPILE_ON_START` (default `1`; legacy `MOJOOBJC_ROUTING_COMPILE_ON_START` also accepted)
- `ARLEN_ROUTING_ROUTE_COMPILE_WARNINGS_AS_ERRORS` (default `0`; legacy `MOJOOBJC_ROUTING_ROUTE_COMPILE_WARNINGS_AS_ERRORS` also accepted)

## `propane` Script (`bin/propane`)

Usage:

```text
propane [options] [-- worker-args]
```

Core options:

- `--workers <n>`
- `--host <addr>`
- `--port <port>`
- `--env <name>`
- `--pid-file <path>`
- `--graceful-shutdown-seconds <n>`
- `--respawn-delay-ms <n>`
- `--reload-overlap-seconds <n>`
- `--listen-backlog <n>`
- `--connection-timeout-seconds <n>`
- `--cluster-enabled`
- `--cluster-name <name>`
- `--cluster-node-id <id>`
- `--cluster-expected-nodes <n>`
- `--job-worker-cmd <command>`
- `--job-worker-count <n>`
- `--job-worker-respawn-delay-ms <n>`
- `--no-respawn`

Async worker environment fallbacks:

- `ARLEN_PROPANE_JOB_WORKER_COMMAND`
- `ARLEN_PROPANE_JOB_WORKER_COUNT`
- `ARLEN_PROPANE_JOB_WORKER_RESPAWN_DELAY_MS`
- `ARLEN_CLUSTER_ENABLED`
- `ARLEN_CLUSTER_NAME`
- `ARLEN_CLUSTER_NODE_ID`
- `ARLEN_CLUSTER_EXPECTED_NODES`
- `ARLEN_CLUSTER_OBSERVED_NODES`

Signals:

- `TERM` / `INT`: graceful shutdown
- `HUP`: rolling worker reload

## Other Helper Scripts and Build Targets

- `bin/test`: run test suite (`make test`)
- `bin/tech-demo`: run technology demo app
- `bin/dev`: alias for `bin/boomhauer`
- `make test-unit` / `make test-integration`: run XCTest bundles with repo-local GNUstep defaults home (`.gnustep-home`)
- `make ci-quality`: run unit + integration + multi-profile perf quality gate
- `make ci-sanitizers`: run ASan/UBSan gate across unit + integration + data-layer checks
- `make phase5e-confidence`: generate Phase 5E release confidence artifacts in `build/release_confidence/phase5e`
- `tools/ci/run_phase5e_quality.sh`: explicit Phase 5E CI gate entrypoint
- `tools/ci/run_phase5e_sanitizers.sh`: explicit Phase 5E sanitizer CI gate entrypoint
  - set `ARLEN_SANITIZER_INCLUDE_INTEGRATION=1` to include full integration suite in sanitizer runs
- `make test-data-layer`: build and run standalone `ArlenData` example validation
- `make deploy-smoke`: validate deployment runbook with automated release smoke
- `tools/deploy/validate_operability.sh`: validate text/JSON health/readiness/metrics operability contracts against a running server
- `tools/deploy/build_release.sh --dry-run --json`: emit deploy release planning payload for coding-agent automation
- `arlen generate frontend <Name> --preset <vanilla-spa|progressive-mpa>`: scaffold frontend starter templates with built-in API wiring examples
- `make docs-api`: regenerate API reference markdown from `Arlen.h` / `ArlenData.h` exports
- `make docs-html`: generate browser-friendly docs under `build/docs`
- `make docs-serve`: serve generated docs locally (default `http://127.0.0.1:4173`, override via `DOCS_PORT`)

## Data-Layer Runtime APIs (Phase 4D)

`ALNPgConnection`/`ALNPg` now provide builder-driven execution helpers with query diagnostics hooks:

- `executeBuilderQuery:error:`
- `executeBuilderCommand:error:`
- `resetExecutionCaches`

Runtime controls:

- `preparedStatementReusePolicy` (`disabled` | `auto` | `always`)
- `preparedStatementCacheLimit`
- `builderCompilationCacheLimit`
- `queryDiagnosticsListener` (event stages: `compile`, `execute`, `result`, `error`)
- `includeSQLInDiagnosticsEvents` (default off for redaction-safe metadata)
- `ARLEN_PHASE5E_SOAK_ITERS` (optional loop count override for Phase 5E soak tests, default `120`)
- `emitDiagnosticsEventsToStderr`

## Service Durability APIs (Phase 7D)

Jobs enqueue options:

- `maxAttempts` (existing retry budget control)
- `idempotencyKey` (new keyed dedupe control while job is pending/leased)

Retry wrappers:

- `ALNRetryingMailAdapter`
  - wraps any `id<ALNMailAdapter>`
  - controls: `maxAttempts`, `retryDelaySeconds`
  - deterministic exhaustion error: `ALNServiceErrorDomain` code `4311`
- `ALNRetryingAttachmentAdapter`
  - wraps any `id<ALNAttachmentAdapter>`
  - controls: `maxAttempts`, `retryDelaySeconds`
  - deterministic exhaustion error: `ALNServiceErrorDomain` code `564`

## PostgreSQL Test Gate

DB-backed tests are skipped unless this environment variable is set:

- `ARLEN_PG_TEST_DSN`: PostgreSQL connection string for migration/adapter tests
