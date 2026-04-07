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
- full-mode scaffold defaults:
  - `templates/layouts/main.html.eoc`
  - `templates/index.html.eoc` with `<%@ layout "layouts/main" %>`
  - `templates/partials/_nav.html.eoc`
  - `templates/partials/_feature.html.eoc`

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
- when `templates/layouts/main.html.eoc` exists, generated HTML templates opt into it automatically unless the target logical path is under `layouts/` or `partials/`

### `arlen migrate [--env <name>] [--database <target>] [--dsn <connection_string>] [--dry-run]`

Apply SQL migrations from `db/migrations` using the configured adapter for the
selected database target.

- `--env <name>`: select runtime environment (default: `development`)
- `--database <target>`: select migration target (default: `default`)
- `--dsn <connection_string>`: override config DSN
- `--dry-run`: list pending migrations without applying
- supported adapters:
  - `postgresql` (default)
  - `gdl2` (fallback compatibility wrapper over PostgreSQL)
  - `mssql` / `sqlserver` (optional SQL Server path via ODBC connection string)
- per-target migration directory: `db/migrations/<target>` (for non-default targets)
- per-target migration state table: `arlen_schema_migrations__<target>`
- target-specific env override: `ARLEN_DATABASE_URL_<TARGET>`
- migration files are executed as raw SQL inside one transaction per file
- normal multi-statement `.sql` migration files are supported
- for MSSQL migrations, standalone `GO` batch separator lines are normalized as
  file-local statement boundaries before execution
- empty/comment-only migration files are rejected
- top-level transaction control statements such as `BEGIN`, `COMMIT`, `ROLLBACK`, `SAVEPOINT`, and `SAVE TRANSACTION` are rejected
- PostgreSQL-specific commands that are disallowed inside transaction blocks still fail under `arlen migrate`
- MSSQL requires an installed ODBC manager/runtime client plus a SQL Server
  driver; core Arlen does not link to Microsoft's driver
- Windows CLANG64 support:
  - supported when the checked-in libpq/ODBC transport discovery contract is satisfied
  - use `arlen doctor` first to confirm DLL/runtime visibility

### `arlen module <add|remove|list|doctor|migrate|assets|upgrade|eject> [options]`

Manage first-class vendored modules installed in `config/modules.plist` and `modules/<id>/`.

`arlen module add <name> [--source <path>] [--force] [--json]`

- installs a local vendored module into `modules/<identifier>`
- updates `config/modules.plist` deterministically
- `--source <path>` points at a module directory containing `module.plist`
- `--force` replaces an existing install in place
- `--json` emits machine-readable workflow output
- first-party modules currently available in-tree:
  - `auth`
  - `admin-ui`
  - `jobs`
  - `notifications`
  - `storage`
  - `ops`
  - `search`

`arlen module remove <name> [--keep-files] [--json]`

- removes the module lock entry
- deletes vendored files unless `--keep-files` is passed

`arlen module list [--json]`

- lists installed module identifiers, versions, principal classes, and install paths

`arlen module doctor [--env <name>] [--json]`

- validates manifests, dependency ordering, compatibility, required config keys, and app-vs-module public mount precedence

`arlen module migrate [--env <name>] [--database <target>] [--dsn <connection_string>] [--dry-run] [--json]`

- applies vendored module migrations in dependency order
- records namespaced migration versions (`<module>::<migration>`) in the normal Arlen migrations table for the selected target
- respects `migrations.databaseTarget` in each module manifest
- uses the configured adapter for the selected target (`postgresql`, `gdl2`, or
  optional `mssql`)

`arlen module assets [--output-dir <path>] [--json]`

- stages module public assets into a deterministic output directory (default `build/module_assets`)
- app overrides under `public/modules/<id>/...` win over module defaults

`arlen module upgrade <name> --source <path> [--force] [--json]`

- replaces the vendored module files and updates the modules lock entry version metadata

`arlen module eject auth-ui [--force] [--json]`

- scaffolds app-owned auth pages under `templates/auth/...`
- scaffolds app-owned auth fragments under `templates/auth/fragments/...`
- scaffolds auth partials under `templates/auth/partials/...`
- scaffolds factor-management pages such as `templates/auth/mfa/manage.html.eoc`
  and `templates/auth/mfa/sms.html.eoc`
- scaffolds `templates/layouts/auth_generated.html.eoc`, `public/auth/auth.css`,
  and `public/auth/auth_totp_qr.js`
- updates `config/app.plist` to use:
  - `authModule.ui.mode = "generated-app-ui"`
  - `authModule.ui.layout = "layouts/auth_generated"`
  - `authModule.ui.generatedPagePrefix = "auth"`
- `--force` overwrites existing generated auth UI files
- `--json` emits machine-readable workflow output with `created_files`, `updated_files`, and `next_steps`

Example first-party bootstrap:

```bash
./build/arlen module add auth
./build/arlen module add admin-ui
./build/arlen module add jobs
./build/arlen module add notifications
./build/arlen module add storage
./build/arlen module add ops
./build/arlen module add search
./build/arlen module migrate --env development
```

Run `arlen module migrate --env <env>` before the first local `auth`
registration or login attempt. If the auth module tables are missing, Arlen
surfaces that setup guidance directly instead of a generic database error.

First-party module surfaces after install:

- `auth`: stable JSON under `/auth/api/...`; HTML ownership under `/auth/...` is controlled by `authModule.ui.mode` (`module-ui`, `headless`, or `generated-app-ui`). Phase 18 also adds embeddable server-rendered MFA fragments, `/auth/api/mfa` factor discovery, and optional disabled-by-default SMS/Twilio Verify MFA support.
- `admin-ui`: HTML under `/admin/...`, JSON under `/admin/api/...`
- `jobs`: protected HTML under `/jobs/...`, JSON under `/jobs/api/...`
- `notifications`: authenticated inbox/preferences plus admin preview/outbox/test-send under `/notifications/...` and `/notifications/api/...`
- `storage`: protected HTML under `/storage/...`, JSON/OpenAPI under `/storage/api/...`, and signed download fetches under `/storage/api/download/:token`
- `ops`: protected HTML under `/ops/...`, JSON/OpenAPI under `/ops/api/...`
- `search`: public query HTML/JSON under `/search/...` plus protected reindex routes under `/search/api/...`

### `arlen schema-codegen [--env <name>] [--database <target>] [--dsn <connection_string>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--typed-contracts] [--force]`

Introspect PostgreSQL schema metadata and generate typed table/column helper APIs.

- current backend scope: PostgreSQL only (`ALNPg`)
- reflection path now goes through `ALNDatabaseInspector` / `ALNPostgresInspector`
- generated manifests now include:
  - `reflection_contract_version`
  - `relation_kind`
  - `read_only`
  - `supports_write_contracts`
  - per-table `column_metadata`
- reflected views retain read-side typed contracts but do not get default write
  builders/contracts
- Phase 20 still does not add MSSQL schema introspection/codegen
- `ALNDatabaseInspector inspectSchemaMetadataForAdapter:` remains PostgreSQL-only
  and now emits additive `schemas`, `check_constraints`, `view_definitions`,
  `relation_comments`, and `column_comments` metadata for audit/reporting tools
- Windows CLANG64 support:
  - supported for PostgreSQL when `libpq` is available through the documented
    DLL discovery contract

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
- app-root non-watch and `--prepare-only` runs reuse `.boomhauer/build/boomhauer-app` when build inputs are unchanged
- app-root non-watch flows emit explicit build phases:
  - `[1/4]` framework tools + libraries
  - `[2/4]` template transpilation
  - `[3/4]` app-object compile/reuse
  - `[4/4]` app-binary link/reuse
- `--prepare-only` prints a prepare-only scope banner and exits after the app is current
- failed app-root `--prepare-only` / `--print-routes` runs preserve the underlying non-zero build status and leave `.boomhauer/last_build_error.{log,meta}` for triage
- `--print-routes` prints a route-inspection scope banner, refreshes artifacts if needed, and then prints resolved routes without entering watch/server mode
- when `ARLEN_FRAMEWORK_ROOT` points at an external checkout whose cached `libArlenFramework.a` still contains ASan/UBSan objects, `boomhauer` rebuilds that framework cleanly before app linking; if sanitizer symbols remain, it fails early with a targeted diagnostic instead of a late raw linker error
- app-root watch mode restarts on config/public changes and rebuilds only when app/framework build inputs change
- vendored module sources under `modules/*/Sources` and module templates under `modules/*/Resources/Templates` are compiled automatically
- app templates under `templates/modules/<id>/...` override vendored module templates with the same logical path
- watch mode builds the fallback dev error server lazily on the first build failure instead of eagerly at startup
- transpile/compile failures in watch mode do not terminate supervisor; diagnostics are served until next successful rebuild
- while the fallback diagnostic server is active, `boomhauer` retries failed builds on a short backoff and the HTML error page advertises that recovery behavior
- server args are passed through (`--watch`, `--no-watch`, `--prepare-only`, `--port`, `--host`, `--env`, `--once`, `--print-routes`)
- Windows CLANG64 support:
  - supported for app-root watch and non-watch flows, including the fallback dev error server retry loop
  - path/bootstrap discovery resolves `GNUstep.sh` dynamically and accepts Windows-owned app-root paths through MSYS normalization

### `arlen jobs worker [worker args...]`

Build and run the first-party jobs worker loop for the current app root.

- delegates to framework `bin/jobs-worker` with `ARLEN_APP_ROOT` + `ARLEN_FRAMEWORK_ROOT`
- compiles the app through `bin/boomhauer --no-watch --prepare-only` and then runs `.boomhauer/build/boomhauer-app` in jobs-worker mode
- if that prepare step fails, exits with the same non-zero status and points at `.boomhauer/last_build_error.log`
- worker args are passed through (`--env`, `--once`, `--limit`, `--poll-interval-seconds`, `--run-scheduler`, `--scheduler-interval-seconds`)
- Windows CLANG64 support:
  - supported natively for app-root workflows through the same prepare-then-run contract as Linux
  - packaged release payloads can also reuse the same framework/app-root contract

### `arlen propane [manager args...]`

Run production manager (`propane`) for the current app root.

- manager args are forwarded to `bin/propane`
- app-root launches first run `bin/boomhauer --no-watch --prepare-only`; if that fails, `propane` exits non-zero and points at `.boomhauer/last_build_error.log`
- all production manager settings are called "propane accessories"
- Windows CLANG64 support:
  - supported natively for app-root workflows, including build-before-launch, reload/shutdown handling, and propane accessories
  - packaged release payloads can also reuse the same framework/app-root contract

### `arlen routes`

Build app and print resolved routes (`--print-routes`).

- Windows CLANG64 support: supported through `bin/boomhauer --no-watch --print-routes`

### `arlen test [--unit|--integration|--all]`

Run framework tests.

- default: equivalent to `--all`
- Windows CLANG64 support:
  - `arlen test --unit` maps to `make test-unit`
  - `arlen test --integration` maps to `make test-integration`
  - `arlen test --all` maps to `make test`

### `arlen perf`

Run performance suite and regression gate (`make perf`).

Profile selection is environment-driven:

- `ARLEN_PERF_PROFILE=default|middleware_heavy|template_heavy|api_reference|migration_sample`
- `ARLEN_PERF_PROFILE=default|middleware_heavy|template_heavy|api_reference|migration_sample|comparison_http`
- `ARLEN_PERF_CONCURRENCY=<n>` (optional concurrent request fanout per scenario)
- `ARLEN_PERF_BASELINE_ROOT=<path>` (optional per-profile baseline directory root)
- `ARLEN_PERF_POLICY_ROOT=<path>` (optional per-profile policy directory root)

### `arlen check [--dry-run] [--json]`

Run quality gate:

- Windows CLANG64 support:
  - maps to `make phase24-windows-parity`
  - runs the checked-in Windows parity sweep, including default unit/integration,
    live-backend, and perf/robustness lanes
- non-Windows:
  - maps to `make check`
  - includes unit tests, integration tests, and perf gate
- `--dry-run`: emit planned make workflow without executing it
- `--json`: emit machine-readable workflow payloads/failure diagnostics (`phase7g-agent-dx-contracts-v1`)

### `arlen build [--dry-run] [--json]`

Build framework targets (`make all`).

- `--dry-run`: emit planned `make all` workflow without executing it
- `--json`: emit machine-readable workflow payloads/failure diagnostics (`phase7g-agent-dx-contracts-v1`)

## `build/eocc`

Template transpiler used by `make`/`boomhauer` pipelines.

Usage:

```text
build/eocc --template-root <dir> --output-dir <dir> [--manifest <file>] [--registry-out <file>] [--logical-prefix <prefix>] <template1.html.eoc> [template2 ...]
```

Behavior:

- `--template-root <dir>`: base tree used to compute deterministic logical template paths
- `--output-dir <dir>`: destination root for generated Objective-C files (`<output-dir>/<logical_path>.m`)
- `--manifest <file>`: enable manifest-backed incremental transpilation
  - records `template_path`, `logical_path`, `output_path`, `template_hash`, metadata, and diagnostics
  - unchanged generated outputs are reused when the manifest and output file still match
  - stale generated outputs are removed when templates move or disappear
  - stdout switches to `eocc: transpiled <n> templates (reused <n>, removed <n>)`
- `--registry-out <file>`: emit registry source mapping logical template paths to render symbols
  - if neither `--manifest` nor `--registry-out` is supplied, `eocc` writes `<output-dir>/EOCRegistry.m`
  - if `--manifest` is supplied without `--registry-out`, `eocc` skips registry generation and removes a stale default `EOCRegistry.m` if present
- `--logical-prefix <prefix>`: prepend a deterministic logical-path prefix before output-path generation
  - used by Arlen's module template pipeline so module templates register under `modules/<module_id>/...`

Diagnostics behavior:

- syntax/transpile failures return non-zero and emit deterministic location metadata:
  - `eocc: location path=<path> line=<line> column=<column>`
- static composition validation failures return non-zero before code generation:
  - unknown `layout` / `include` / `render` dependencies
  - static composition cycles across layouts/includes/renders
- lint warnings are emitted during successful transpile:
  - `eocc: warning path=<path> line=<line> column=<column> code=<code> message=<message>`
  - current lint codes:
    - `unguarded_include`
    - `slot_without_layout`
    - `unused_slot_fill`
- lint warnings are non-fatal in this phase slice
- sigil local grammar supports:
  - `$identifier`
  - `$identifier(.identifier)*` (dotted keypaths)
- composition directives support:
  - `<%@ layout "layouts/application" %>`
  - `<%@ requires title, rows %>`
  - `<%@ yield %>` / `<%@ yield "sidebar" %>`
  - `<%@ slot "sidebar" %>` ... `<%@ endslot %>`
  - `<%@ include "partials/_row" with @{ ... } %>`
  - `<%@ render "partials/_row" collection:$rows as:"row" empty:"partials/_empty" with @{ ... } %>`

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
- app-root builds are cached at `.boomhauer/build/boomhauer-app` with a persistent fingerprint
- unchanged app-root build inputs skip template transpile/clang on subsequent `--no-watch` / `--prepare-only` launches
- failed app-root `--prepare-only` / `--print-routes` runs preserve the underlying non-zero build status and surface `.boomhauer/last_build_error.log` before exiting
- if an external `ARLEN_FRAMEWORK_ROOT` points at cached ASan/UBSan framework artifacts, `boomhauer` forces a clean framework rebuild before app linking and otherwise emits an explicit compatibility diagnostic
- watch mode restarts on config/public changes without forcing a rebuild when the cached app binary is still current
- watch mode builds the fallback framework error server only when it needs to serve a build-failure page
- current build fingerprint covers app `src/`, `templates/`, `app_lite.m`, framework `src/`, framework `GNUmakefile`, `tools/eocc.m`, and compile toggles `ARLEN_ENABLE_YYJSON` / `ARLEN_ENABLE_LLHTTP`
- compile path enforces `-fobjc-arc` for app/framework/generated Objective-C sources
- repository build pipeline enforces ARC across first-party Objective-C compile paths (GNUmakefile + boomhauer)
- `EXTRA_OBJC_FLAGS` may add flags (for example sanitizers) but may not include `-fno-objc-arc`
- repository build artifacts are invalidated when compile toggles or `EXTRA_OBJC_FLAGS` change so sanitizer-built tools are not reused in normal lanes
- defaults to watch mode
- in app-root watch mode, build failures are captured and rendered as development diagnostics
- fallback build-error responses include last-failure timestamp, recovery hint, no-store cache headers, and browser auto-refresh metadata
- watch mode retries failed builds automatically (`ARLEN_BOOMHAUER_BUILD_ERROR_RETRY_SECONDS`, default `2`) even when no additional watched-file fingerprint change is observed
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
- security misconfiguration now fails startup deterministically:
  - missing `session.secret` when `session.enabled=YES`
  - weak `session.secret` values (minimum 32 characters required when `session.enabled=YES`)
  - weak `auth.bearerSecret` values (minimum 32 characters required when `auth.enabled=YES`)
  - `csrf.enabled=YES` without session middleware
  - query-string CSRF fallback is disabled by default; opt in with `ARLEN_CSRF_ALLOW_QUERY_FALLBACK=1`
- when `webSocket.allowedOrigins` is configured, websocket upgrades require a matching `Origin` header or return `403`
- the legacy HTTP parser backend rejects duplicate `Content-Length` headers and all `Transfer-Encoding` requests
- session middleware stores cookies as encrypted and authenticated tokens by default
- route-level auth assurance can be configured with `configureAuthAssuranceForRouteNamed:minimumAuthAssuranceLevel:maximumAuthenticationAgeSeconds:stepUpPath:error:`
- browser requests that fail an auth-assurance requirement return `302` to the configured step-up path with:
  - header `X-Arlen-Step-Up-Required: 1`
  - query params `reason=step_up_required` and `return_to=<original path>`
- JSON/API requests that fail an auth-assurance requirement return structured `403 step_up_required`
- Phase 12 public helper surface:
  - `ALNAuthSession`
  - `ALNTOTP`
  - `ALNRecoveryCodes`
  - `ALNWebAuthn`
  - `ALNOIDCClient`
  - `ALNAuthProviderPresets`
  - `ALNAuthProviderSessionBridge`
- `make phase12-confidence` runs the Phase 12 auth confidence gate and writes artifacts under `build/release_confidence/phase12`
- forwarded proxy headers are honored only when the peer IP matches `trustedProxyCIDRs`
  - specifying `trustedProxyCIDRs` alone enables forwarded-header handling
  - `trustedProxy=YES` remains as a compatibility toggle and seeds a loopback CIDR allowlist when no explicit CIDRs are configured
  - `edge` profile defaults `trustedProxyCIDRs` to `127.0.0.1/32`
- text logger output escapes newline/tab/control characters in text mode
- filesystem job/mail/attachment adapters enforce private `0700` directories and `0600` files; filesystem attachment IDs must be framework-generated `att-<32 hex>` values
- route compile validation now fails startup deterministically when enabled (`routing.compileOnStart=YES`):
  - invalid action/guard signatures
  - invalid route schema transformer/type readiness
- request responses emit correlation/trace headers by default:
  - `X-Request-Id`
  - `X-Correlation-Id`
  - disable request/correlation headers with `ARLEN_RESPONSE_IDENTITY_HEADERS_ENABLED=0`
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
- `ARLEN_TRUSTED_PROXY` (legacy compatibility toggle for forwarded-header handling; when set to `1` with no explicit CIDRs, Arlen falls back to `127.0.0.1/32`; legacy `MOJOOBJC_TRUSTED_PROXY` also accepted)
- `ARLEN_TRUSTED_PROXY_CIDRS` (comma-separated IPv4 CIDR allowlist for trusted reverse proxies; setting this list alone enables forwarded-header handling; legacy `MOJOOBJC_TRUSTED_PROXY_CIDRS` also accepted)
- `ARLEN_MAX_HTTP_SESSIONS` (runtime HTTP session limit; legacy `MOJOOBJC_MAX_HTTP_SESSIONS` also accepted)
- `ARLEN_MAX_WEBSOCKET_SESSIONS` (runtime websocket session limit; legacy `MOJOOBJC_MAX_WEBSOCKET_SESSIONS` also accepted)
- `ARLEN_WEBSOCKET_ALLOWED_ORIGINS` (comma-separated websocket `Origin` allowlist; normalized to scheme/host/port; legacy `MOJOOBJC_WEBSOCKET_ALLOWED_ORIGINS` also accepted)
- `ARLEN_MAX_HTTP_WORKERS` (runtime HTTP worker pool size; legacy `MOJOOBJC_MAX_HTTP_WORKERS` also accepted)
- `ARLEN_MAX_QUEUED_HTTP_CONNECTIONS` (runtime HTTP worker queue depth; legacy `MOJOOBJC_MAX_QUEUED_HTTP_CONNECTIONS` also accepted)
- `ARLEN_MAX_REALTIME_SUBSCRIBERS` (runtime global realtime subscriber cap; legacy `MOJOOBJC_MAX_REALTIME_SUBSCRIBERS` also accepted)
- `ARLEN_MAX_REALTIME_SUBSCRIBERS_PER_CHANNEL` (runtime per-channel realtime subscriber cap; legacy `MOJOOBJC_MAX_REALTIME_SUBSCRIBERS_PER_CHANNEL` also accepted)
- `ARLEN_REQUEST_DISPATCH_MODE` (`concurrent` or `serialized`; defaults to `concurrent`; legacy `MOJOOBJC_REQUEST_DISPATCH_MODE` also accepted)
- `ARLEN_HTTP_PARSER_BACKEND` (`llhttp` default when compiled in; `legacy` fallback/override)
- `ARLEN_ENABLE_YYJSON` (compile-time toggle for app-root builds via `bin/boomhauer`; `1` default, set `0` to compile without yyjson)
- `ARLEN_ENABLE_LLHTTP` (compile-time toggle for app-root builds via `bin/boomhauer`; `1` default, set `0` to compile without llhttp)
- `ARLEN_BOOMHAUER_BUILD_ERROR_RETRY_SECONDS` (watch-mode fallback retry cadence in seconds; default `2`; set `0` to disable automatic retry)
- `ARLEN_BOOMHAUER_BUILD_ERROR_AUTO_REFRESH_SECONDS` (fallback HTML auto-refresh cadence in seconds; default `3`; set `0` to disable automatic refresh)
- `ARLEN_BOOMHAUER_BUILD_ERROR_RECOVERY_HINT` (optional custom recovery text shown on the fallback HTML page and JSON diagnostics; compile failures keep Clang-style color highlighting in the browser page while JSON stays plain-text-safe)
- `ARLEN_TRACE_PROPAGATION_ENABLED` (default `1`; legacy `MOJOOBJC_TRACE_PROPAGATION_ENABLED` also accepted)
- `ARLEN_RESPONSE_IDENTITY_HEADERS_ENABLED` (default `1`; disables `X-Request-Id`/`X-Correlation-Id` emission when set to `0`; legacy `MOJOOBJC_RESPONSE_IDENTITY_HEADERS_ENABLED` also accepted)
- `ARLEN_METRICS_ENABLED` (default `1`; disables hot-path metrics writes when set to `0`; legacy `MOJOOBJC_METRICS_ENABLED` also accepted)
- `ARLEN_HEALTH_DETAILS_ENABLED` (default `1`; legacy `MOJOOBJC_HEALTH_DETAILS_ENABLED` also accepted)
- `ARLEN_READINESS_REQUIRES_STARTUP` (default `0`; legacy `MOJOOBJC_READINESS_REQUIRES_STARTUP` also accepted)
- `ARLEN_READINESS_REQUIRES_CLUSTER_QUORUM` (default `0`; legacy `MOJOOBJC_READINESS_REQUIRES_CLUSTER_QUORUM` also accepted)
- `ARLEN_CLUSTER_OBSERVED_NODES` (defaults to expected nodes; legacy `MOJOOBJC_CLUSTER_OBSERVED_NODES` also accepted)
- `ARLEN_ROUTING_COMPILE_ON_START` (default `1`; legacy `MOJOOBJC_ROUTING_COMPILE_ON_START` also accepted)
- `ARLEN_ROUTING_ROUTE_COMPILE_WARNINGS_AS_ERRORS` (default `0`; legacy `MOJOOBJC_ROUTING_ROUTE_COMPILE_WARNINGS_AS_ERRORS` also accepted)

## `jobs-worker` Script (`bin/jobs-worker`)

Usage:

```text
jobs-worker [options]
```

Behavior:

- compiles the current app root through `bin/boomhauer --no-watch --prepare-only`
- if that prepare step fails, exits with the same non-zero status and points at `.boomhauer/last_build_error.log`
- launches `.boomhauer/build/boomhauer-app` in first-party jobs-worker mode
- compiled app binaries now honor `ARLEN_APP_ROOT`, so `arlen jobs worker`, `bin/jobs-worker`, and `propane` all resolve the correct config/public roots even when invoked from the framework checkout

Options:

- `--env <name>`
- `--app-root <path>`
- `--framework-root <path>`
- `--once`
- `--limit <n>`
- `--poll-interval-seconds <seconds>`
- `--run-scheduler`
- `--scheduler-interval-seconds <seconds>`
- `--help` / `-h`

Environment:

- `ARLEN_APP_ROOT`
- `ARLEN_FRAMEWORK_ROOT`

## `propane` Script (`bin/propane`)

Usage:

```text
propane [options] [-- worker-args]
```

Behavior:

- in app-root mode, runs `bin/boomhauer --no-watch --prepare-only` before launching workers
- if that prepare step fails, exits with the same non-zero status and points at `.boomhauer/last_build_error.log`

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
- `bin/jobs-worker`: build current app and run the first-party jobs worker loop
- `make build-tests`: build unit + integration bundles through the incremental
  object/archive/template graph without running XCTest
- `make test-unit` / `make test-integration`: run XCTest bundles with repo-local GNUstep defaults home (`.gnustep-home`)
  - honor `ARLEN_XCTEST` as the runner override (default `xctest`)
  - honor `ARLEN_XCTEST_LD_LIBRARY_PATH` when the selected runner needs a non-system `libXCTest`
- `make test-unit-filter` / `make test-integration-filter`: focused XCTest reruns using `TEST=TestClass[/testMethod]` and optional `SKIP_TEST=TestClass[/testMethod]`
  - Arlen prepends the bundle target name automatically, so you do not include `ArlenUnitTests/` or `ArlenIntegrationTests/` in `TEST`
  - require an XCTest runner that supports Apple-style `-only-testing` / `-skip-testing` arguments; stock Debian `tools-xctest` may not provide those flags yet
  - if the patched runner comes from a local `tools-xctest` build tree, also set `ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj`
  - example: `ARLEN_XCTEST=/path/to/patched/xctest ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj make test-unit-filter TEST=RuntimeTests/testRenderAndIncludeNormalizeUnsuffixedTemplateReferences`
- `make phase20-sql-builder-tests` / `make phase20-schema-tests` / `make phase20-routing-tests`: focused Phase 20 pure-unit lanes that do not depend on `-only-testing`
- `make phase20-postgres-live-tests` / `make phase20-mssql-live-tests`: focused Phase 20 live-backend lanes with explicit DSN/transport requirement logging
- `make phase20-focused`: run the full focused Phase 20 lane set without relying on stock `xctest -only-testing`
- `make phase21-template-tests`: focused template parser/codegen/security/regression bundle
- `make phase21-protocol-tests`: Phase 21 raw protocol corpus replay across the configured parser backends
- `make phase21-generated-app-tests`: curated generated-app/module/config matrix for first-user flows
- `make phase21-focused`: run the full focused Phase 21 lane set
- `make phase21-confidence`: rerun the focused Phase 21 lanes and regenerate artifacts under `build/release_confidence/phase21`
- `make phase24-windows-tests`: focused Windows XCTest lane using the linked `ArlenPhase21TemplateTestsRunner`
- `make phase24-windows-db-smoke`: focused Windows transport-loading smoke lane
- `make phase24-windows-runtime-tests`: focused Windows runtime parity lane using the linked `ArlenPhase24WindowsRuntimeParityTestsRunner`
- `make phase24-windows-confidence`: Windows build/test/runtime/app-root confidence lane
- `make phase24-windows-parity`: full Windows `24Q-24R` parity lane
  - runs build, default unit/integration entrypoints, PostgreSQL/MSSQL live-backend suites, and the broader perf/robustness scripts wired through `tools/ci/run_phase24_windows_parity.sh`
- `tools/ci/run_phase21_focused.sh`: explicit focused Phase 21 lane runner for template, protocol, and generated-app coverage
- `tools/ci/run_phase21_protocol_corpus.sh`: explicit Phase 21 raw protocol corpus gate entrypoint
  - `ARLEN_PHASE21_PROTOCOL_BACKENDS=llhttp` narrows replay to one parser backend
  - `ARLEN_PHASE21_PROTOCOL_CASES=case_a,case_b` reruns only selected checked-in protocol cases
- `tools/ci/phase21_protocol_replay.py`: replay one checked-in protocol case or one saved raw request
  - example checked-in case: `python3 tools/ci/phase21_protocol_replay.py --case websocket_invalid_key --backends llhttp --output-dir build/release_confidence/phase21/protocol_replay`
  - example saved seed: `python3 tools/ci/phase21_protocol_replay.py --raw-request tests/fixtures/protocol/fuzz_seeds/websocket_invalid_key_seed.http --expected-status 400 --case-id websocket_invalid_key_seed --backends llhttp`
- `tools/ci/run_phase21_generated_app_matrix.sh`: explicit Phase 21 generated-app matrix entrypoint
- `make browser-error-audit`: run the dedicated browser error audit bundle and generate a review gallery at `build/browser-error-audit/index.html`
  - captures representative build/runtime/browser error scenarios into browsable HTML artifacts
  - preserves raw responses plus wrapped review pages so plain-text/JSON browser fallbacks are easy to inspect
- `make ci-perf-smoke`: run the lighter standalone macro perf smoke lane for the checked-in `default` and `template_heavy` profiles and archive artifacts under `build/perf/ci_smoke`
  - intended for local/manual perf triage; `make ci-quality` already covers the broader multi-profile macro perf matrix in CI
- `make ci-quality`: run unit + integration + multi-profile perf quality gate plus runtime concurrency, JSON abstraction/performance gates, and Phase 9I fault-injection checks
- `make ci-sanitizers`: run the Phase 10M ASan/UBSan sanitizer matrix (unit, runtime probe, backend parity, fault injection, soak, chaos restart, static analysis) and generate artifacts under `build/release_confidence/phase10m/sanitizers`
- `make ci-fault-injection`: run Phase 9I runtime seam fault-injection matrix and generate artifacts under `build/release_confidence/phase9i`
- `make ci-release-certification`: run Phase 9J enterprise release checklist and generate certification artifacts under `build/release_confidence/phase9j`
- `make ci-json-abstraction`: fail when runtime sources bypass `ALNJSONSerialization`
- `make ci-json-perf`: run Phase 10E JSON backend microbenchmark gate and generate artifacts under `build/release_confidence/phase10e`
- `make ci-dispatch-perf`: run Phase 10G dispatch invocation benchmark gate and generate artifacts under `build/release_confidence/phase10g`
- `make ci-http-parse-perf`: run Phase 10H HTTP parser benchmark gate and generate artifacts under `build/release_confidence/phase10h`
- `make ci-phase11-protocol-adversarial`: run the Phase 11 hostile protocol corpus and generate artifacts under `build/release_confidence/phase11/protocol_adversarial`
- `make ci-phase11-fuzz`: run the Phase 11 deterministic protocol mutation harness and generate artifacts under `build/release_confidence/phase11/protocol_fuzz`
- `make ci-phase11-live-adversarial`: run the Phase 11 mixed hostile HTTP/websocket probe and generate artifacts under `build/release_confidence/phase11/live_adversarial`
- `make ci-phase11-sanitizers`: run the Phase 11 ASan/UBSan hostile-traffic matrix and generate artifacts under `build/release_confidence/phase11/sanitizers`
- `make ci-phase11`: run the full Phase 11 confidence pack (protocol corpus + fuzz + live probe + sanitizer matrix)
- `make phase5e-confidence`: generate Phase 5E release confidence artifacts in `build/release_confidence/phase5e`
- `make phase14-confidence`: run the Phase 14 module confidence gate and generate artifacts in `build/release_confidence/phase14`
- `make phase15-confidence`: run the Phase 15 auth UI confidence gate and generate artifacts in `build/release_confidence/phase15`
- `make phase16-confidence`: run the Phase 16 module-maturity confidence gate and generate artifacts in `build/release_confidence/phase16`
- `make phase19-confidence`: run the Phase 19 incremental build-graph confidence gate and generate artifacts in `build/release_confidence/phase19`
- `make phase20-confidence`: generate Phase 20 reflection/type-codec/backend-tier confidence artifacts in `build/release_confidence/phase20`
- `tools/ci/run_phase20_focused.sh`: explicit focused Phase 20 lane runner for builder/schema/routing plus PostgreSQL/MSSQL live coverage
- `tools/ci/run_phase5e_quality.sh`: explicit Phase 5E CI gate entrypoint
- `tools/ci/run_phase5e_sanitizers.sh`: explicit Phase 5E sanitizer CI gate entrypoint
  - remains the explicit Phase 9H-style blocking lane for ASan/UBSan unit + runtime/data-layer checks plus Phase 9H confidence artifact generation under `build/release_confidence/phase9h`
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
- `tools/ci/run_perf_smoke.sh`: explicit macro perf-smoke entrypoint used by `make ci-perf-smoke`
  - kept standalone because the self-hosted Phase 5E quality workflow already runs the fuller macro perf matrix
  - `ARLEN_PERF_SMOKE_PROFILES` selects the checked-in macro perf profiles to gate (default `default,template_heavy`)
  - `ARLEN_PERF_SMOKE_REQUESTS` overrides requests per scenario (default `120`)
  - `ARLEN_PERF_SMOKE_REPEATS` overrides median-aggregation repeats (default `3`)
  - `ARLEN_PERF_SMOKE_OUTPUT_DIR` overrides the artifact output directory
  - `ARLEN_PERF_SMOKE_SKIP_BUILD=1` reuses already-built binaries across profiles
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
- `tools/ci/run_phase11_protocol_adversarial.sh`: explicit Phase 11 hostile protocol corpus gate entrypoint
  - `ARLEN_PHASE11_PROTOCOL_OUTPUT_DIR` overrides artifact output directory
  - `ARLEN_PHASE11_PROTOCOL_BACKENDS` selects parser backends (default `llhttp,legacy`)
- `tools/ci/run_phase11_protocol_fuzz.sh`: explicit Phase 11 deterministic protocol mutation gate entrypoint
  - `ARLEN_PHASE11_FUZZ_OUTPUT_DIR` overrides artifact output directory
  - `ARLEN_PHASE11_FUZZ_BACKENDS` selects parser backends (default `llhttp,legacy`)
- `tools/ci/run_phase11_live_adversarial.sh`: explicit Phase 11 mixed hostile-traffic probe entrypoint
  - `ARLEN_PHASE11_LIVE_OUTPUT_DIR` overrides artifact output directory
  - `ARLEN_PHASE11_LIVE_MODES` selects dispatch modes (default `serialized,concurrent`)
  - `ARLEN_PHASE11_LIVE_ROUNDS` controls probe rounds (default `2`)
- `tools/ci/run_phase11_sanitizer_matrix.sh`: explicit Phase 11 sanitizer hostile-traffic matrix entrypoint
  - `ARLEN_PHASE11_SANITIZER_OUTPUT_DIR` overrides artifact output directory
  - `ARLEN_PHASE11_SANITIZER_LANES` selects sanitizer lanes
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
- `make ci-docs`: run docs quality gate (API docs regen consistency + roadmap summary consistency + newcomer-doc navigation checks + imported comparative benchmark-contract consistency + HTML artifact/link checks)
- `make ci-benchmark-contracts`: validate the imported lightweight comparative benchmark fixtures under `tests/fixtures/benchmarking/`
- `tools/ci/run_docs_quality.sh`: docs-quality CI entrypoint used by `make ci-docs` and workflow gate
- `tools/ci/check_roadmap_consistency.py`: validates that `README.md`, `docs/STATUS.md`, and historical aggregate/index docs stay aligned with the authoritative per-phase roadmap headers
- `tools/ci/check_docs_navigation.py`: validates newcomer-facing docs sections, key links, and required guide files
- `tools/ci/check_benchmark_contracts.py`: validates the imported comparative benchmark manifests/config contract pack and the source-of-truth bridge notes in `docs/COMPARATIVE_BENCHMARKING.md`
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

## Live-Backend Test Gates

DB-backed tests are skipped unless the matching environment variables are set:

- `ARLEN_PG_TEST_DSN`: PostgreSQL connection string for migration/adapter/live-backend tests
- `ARLEN_LIBPQ_LIBRARY`: optional explicit `libpq` path when platform autodiscovery is insufficient
- `ARLEN_PSQL`: optional explicit `psql` path for helper scripts that need the native PostgreSQL client
- `ARLEN_MSSQL_TEST_DSN`: SQL Server ODBC connection string for the MSSQL live-backend suite
- `ARLEN_ODBC_LIBRARY`: optional explicit ODBC client library override; on Windows parity hosts use `odbc32.dll`

On Windows CLANG64 parity hosts, `tools/ci/_phase24_windows_env.sh` can fill
the checked-in PostgreSQL defaults and a LocalDB-backed SQL Server DSN
automatically when those variables are unset.
