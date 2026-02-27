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
- `--json`: deterministic pretty JSON output (sorted keys when runtime supports `NSJSONWritingSortedKeys`)

## `boomhauer` Script (`bin/boomhauer`)

Usage:

```text
boomhauer [options]
```

Behavior:

- if run inside app root (`config/app.plist` plus `src/main.m` or `app_lite.m`), compiles and runs that app
- compile path enforces `-fobjc-arc` for app/framework/generated Objective-C sources
- repository build pipeline enforces ARC across first-party Objective-C compile paths (GNUmakefile + boomhauer)
- `EXTRA_OBJC_FLAGS` may add flags (for example sanitizers) but may not include `-fno-objc-arc`
- defaults to watch mode
- in app-root watch mode, build failures are captured and rendered as development diagnostics
- concurrent HTTP sessions are bounded by `runtimeLimits.maxConcurrentHTTPSessions` (default `256`)
- websocket session upgrades are bounded by `runtimeLimits.maxConcurrentWebSocketSessions` (default `256`)
- request dispatch mode is controlled by `requestDispatchMode` (`concurrent` default)
  - `serialized` mode keeps dispatch execution deterministic while still honoring HTTP keep-alive negotiation
- HTTP session limit violations return deterministic overload diagnostics:
  - status `503 Service Unavailable`
  - header `Retry-After: 1`
  - header `X-Arlen-Backpressure-Reason: http_session_limit`
- HTTP worker queue overflow returns deterministic overload diagnostics:
  - status `503 Service Unavailable`
  - header `Retry-After: 1`
  - header `X-Arlen-Backpressure-Reason: http_worker_queue_full`
- websocket backpressure limit violations return deterministic overload diagnostics:
  - status `503 Service Unavailable`
  - header `Retry-After: 1`
  - header `X-Arlen-Backpressure-Reason: websocket_session_limit`
- realtime channel subscription cap violations return deterministic overload diagnostics:
  - status `503 Service Unavailable`
  - header `Retry-After: 1`
  - header `X-Arlen-Backpressure-Reason: realtime_channel_subscriber_limit`
- realtime global subscription cap violations return deterministic overload diagnostics:
  - status `503 Service Unavailable`
  - header `Retry-After: 1`
  - header `X-Arlen-Backpressure-Reason: realtime_total_subscriber_limit`
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
  - response headers `X-Arlen-Cluster-Status`, `X-Arlen-Cluster-Observed-Nodes`, and `X-Arlen-Cluster-Expected-Nodes` (when `cluster.enabled=YES` and `cluster.emitHeaders=YES`)
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
- `ARLEN_MAX_HTTP_SESSIONS` (runtime HTTP session limit; legacy `MOJOOBJC_MAX_HTTP_SESSIONS` also accepted)
- `ARLEN_MAX_WEBSOCKET_SESSIONS` (runtime websocket session limit; legacy `MOJOOBJC_MAX_WEBSOCKET_SESSIONS` also accepted)
- `ARLEN_MAX_HTTP_WORKERS` (runtime HTTP worker pool size; legacy `MOJOOBJC_MAX_HTTP_WORKERS` also accepted)
- `ARLEN_MAX_QUEUED_HTTP_CONNECTIONS` (runtime HTTP worker queue depth; legacy `MOJOOBJC_MAX_QUEUED_HTTP_CONNECTIONS` also accepted)
- `ARLEN_MAX_REALTIME_SUBSCRIBERS` (runtime global realtime subscriber cap; legacy `MOJOOBJC_MAX_REALTIME_SUBSCRIBERS` also accepted)
- `ARLEN_MAX_REALTIME_SUBSCRIBERS_PER_CHANNEL` (runtime per-channel realtime subscriber cap; legacy `MOJOOBJC_MAX_REALTIME_SUBSCRIBERS_PER_CHANNEL` also accepted)
- `ARLEN_REQUEST_DISPATCH_MODE` (`concurrent` or `serialized`; defaults to `concurrent`; legacy `MOJOOBJC_REQUEST_DISPATCH_MODE` also accepted)
- `ARLEN_JSON_BACKEND` (`yyjson` default, `foundation`/`nsjson` fallback for A/B validation; foundation fallback deprecation target: `2026-04-30`)
- `ARLEN_HTTP_PARSER_BACKEND` (`llhttp` default when compiled in; `legacy` fallback/override)
- `ARLEN_ENABLE_YYJSON` (compile-time toggle for app-root builds via `bin/boomhauer`; `1` default, set `0` to compile without yyjson)
- `ARLEN_ENABLE_LLHTTP` (compile-time toggle for app-root builds via `bin/boomhauer`; `1` default, set `0` to compile without llhttp)
- `ARLEN_TRACE_PROPAGATION_ENABLED` (default `1`; legacy `MOJOOBJC_TRACE_PROPAGATION_ENABLED` also accepted)
- `ARLEN_METRICS_ENABLED` (default `1`; disables hot-path metrics writes when set to `0`; legacy `MOJOOBJC_METRICS_ENABLED` also accepted)
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
- `ARLEN_PROPANE_LIFECYCLE_LOG` (optional file path for structured lifecycle diagnostics)
- `ARLEN_CLUSTER_ENABLED`
- `ARLEN_CLUSTER_NAME`
- `ARLEN_CLUSTER_NODE_ID`
- `ARLEN_CLUSTER_EXPECTED_NODES`
- `ARLEN_CLUSTER_OBSERVED_NODES`
- `ARLEN_REQUEST_DISPATCH_MODE` (`concurrent` by default in workers)

Signals:

- `TERM` / `INT`: graceful shutdown
- `HUP`: rolling worker reload

Lifecycle diagnostics:

- stdout emits deterministic lines prefixed with `propane:lifecycle`
- line contract: `event=<name> manager_pid=<pid> key=value ...`
- worker churn fields include stable `status`, `exit_reason`, `restart_action`, and `reason`

## Other Helper Scripts and Build Targets

- `bin/test`: run test suite (`make test`)
- `bin/tech-demo`: run technology demo app
- `bin/dev`: alias for `bin/boomhauer`
- `make test-unit` / `make test-integration`: run XCTest bundles with repo-local GNUstep defaults home (`.gnustep-home`)
- `make ci-quality`: run unit + integration + multi-profile perf quality gate plus runtime concurrency, JSON abstraction/performance gates, and Phase 9I fault-injection checks
- `make ci-sanitizers`: run Phase 9H blocking sanitizer gate (ASan/UBSan + runtime probe + data-layer checks), validate suppression registry, and generate sanitizer confidence artifacts under `build/release_confidence/phase9h`
- `make ci-fault-injection`: run Phase 9I runtime seam fault-injection matrix and generate artifacts under `build/release_confidence/phase9i`
- `make ci-release-certification`: run Phase 9J enterprise release checklist and generate certification artifacts under `build/release_confidence/phase9j`
- `make ci-json-abstraction`: fail when runtime sources bypass `ALNJSONSerialization`
- `make ci-json-perf`: run Phase 10E JSON backend microbenchmark gate and generate artifacts under `build/release_confidence/phase10e`
- `make ci-dispatch-perf`: run Phase 10G dispatch invocation benchmark gate and generate artifacts under `build/release_confidence/phase10g`
- `make ci-http-parse-perf`: run Phase 10H HTTP parser benchmark gate and generate artifacts under `build/release_confidence/phase10h`
- `make phase5e-confidence`: generate Phase 5E release confidence artifacts in `build/release_confidence/phase5e`
- `tools/ci/run_phase5e_quality.sh`: explicit Phase 5E CI gate entrypoint
- `tools/ci/run_phase5e_sanitizers.sh`: explicit Phase 5E sanitizer CI gate entrypoint
  - set `ARLEN_SANITIZER_INCLUDE_INTEGRATION=1` to include full integration suite (default is `0`)
  - set `ARLEN_SANITIZER_INCLUDE_TSAN=1` to run TSAN experimental lane (non-blocking)
- `tools/ci/run_phase5e_tsan_experimental.sh`: execute TSAN experimental lane directly and retain artifacts in `build/sanitizers/tsan`
- `tools/ci/run_phase9i_fault_injection.sh`: explicit Phase 9I fault-injection gate entrypoint
  - `ARLEN_PHASE9I_SEED` controls replay seed (default `9011`)
  - `ARLEN_PHASE9I_ITERS` controls iterations per mode (default `1`)
  - `ARLEN_PHASE9I_MODES` selects modes (`concurrent,serialized` by default)
  - `ARLEN_PHASE9I_SCENARIOS` selects optional scenario subset (comma-separated)
  - `ARLEN_PHASE9I_OUTPUT_DIR` overrides artifact output directory
- `tools/ci/run_phase9j_release_certification.sh`: explicit Phase 9J release-certification gate entrypoint
  - `ARLEN_PHASE9J_RELEASE_ID` sets the release-candidate id in generated pack metadata
  - `ARLEN_PHASE9J_OUTPUT_DIR` overrides artifact output directory
  - `ARLEN_PHASE9J_SKIP_GATES=1` skips gate execution and regenerates certification from existing artifacts
  - `ARLEN_PHASE9J_ALLOW_INCOMPLETE=1` emits an incomplete pack without failing the command
- `tools/ci/run_phase10e_json_performance.sh`: explicit Phase 10E JSON backend performance gate entrypoint
  - `ARLEN_PHASE10E_ITERATIONS` controls benchmark iterations (default `1500`)
  - `ARLEN_PHASE10E_WARMUP` controls warmup iterations (default `200`)
  - `ARLEN_PHASE10E_ROUNDS` controls median-aggregation benchmark rounds (default `3`)
  - `ARLEN_PHASE10E_OUTPUT_DIR` overrides artifact output directory
  - `ARLEN_PHASE10E_FIXTURES_DIR` overrides fixture corpus directory
  - `ARLEN_PHASE10E_THRESHOLDS` overrides threshold policy fixture path
- `tools/ci/run_phase10g_dispatch_performance.sh`: explicit Phase 10G dispatch benchmark gate entrypoint
  - `ARLEN_PHASE10G_ITERATIONS` controls benchmark iterations (default `50000`)
  - `ARLEN_PHASE10G_WARMUP` controls warmup iterations (default `5000`)
  - `ARLEN_PHASE10G_ROUNDS` controls median-aggregation benchmark rounds (default `3`)
  - `ARLEN_PHASE10G_OUTPUT_DIR` overrides artifact output directory
  - `ARLEN_PHASE10G_THRESHOLDS` overrides threshold policy fixture path
- `tools/ci/run_phase10h_http_parse_performance.sh`: explicit Phase 10H HTTP parser benchmark gate entrypoint
  - `ARLEN_PHASE10H_ITERATIONS` controls benchmark iterations (default `1500`)
  - `ARLEN_PHASE10H_WARMUP` controls warmup iterations (default `200`)
  - `ARLEN_PHASE10H_ROUNDS` controls median-aggregation benchmark rounds (default `5`)
  - `ARLEN_PHASE10H_OUTPUT_DIR` overrides artifact output directory
  - `ARLEN_PHASE10H_FIXTURES_DIR` overrides fixture corpus directory
  - `ARLEN_PHASE10H_THRESHOLDS` overrides threshold policy fixture path
  - threshold policy supports global + fixture-size classes:
    - global: `parse_ops_ratio_min`, `parse_p95_ratio_max`, expected-improvement keys
    - small fixture class: `small_request_bytes_max`, `small_parse_ops_ratio_min`, `small_parse_p95_ratio_max`
    - large fixture class: `large_request_bytes_min`, `large_parse_ops_ratio_min`, `large_parse_p95_ratio_max`
- `make test-data-layer`: build and run standalone `ArlenData` example validation
- `make parity-phaseb`: run Arlen-vs-FastAPI Phase B parity gate for frozen benchmark scenarios (creates report at `build/perf/parity_fastapi_latest.json`)
- `make perf-phasec`: run Phase C benchmark protocol (warmup + concurrency ladder) and write `build/perf/phasec/latest_protocol_report.json`
- `make perf-phased`: run Phase D baseline campaign (parity + Arlen/FastAPI matrix) and write `build/perf/phased/latest_campaign_report.json`
- `make deploy-smoke`: validate deployment runbook with automated release smoke
- `tools/deploy/validate_operability.sh`: validate text/JSON health/readiness/metrics operability contracts against a running server
- `tools/deploy/build_release.sh --dry-run --json`: emit deploy release planning payload for coding-agent automation
  - enforces Phase 9J certification manifest by default (`build/release_confidence/phase9j/manifest.json`)
  - enforces Phase 10E JSON performance manifest by default (`build/release_confidence/phase10e/manifest.json`)
  - use `--certification-manifest <path>` to override manifest location
  - use `--json-performance-manifest <path>` to override JSON performance manifest location
  - use `--allow-missing-certification` only for non-RC smoke/local packaging flows
- `arlen generate frontend <Name> --preset <vanilla-spa|progressive-mpa>`: scaffold frontend starter templates with built-in API wiring examples
- `make ci-docs`: run docs quality gate (API docs regen consistency + HTML artifact/link checks)
- `tools/ci/run_docs_quality.sh`: docs-quality CI entrypoint used by `make ci-docs` and workflow gate
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
