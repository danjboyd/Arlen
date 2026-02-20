# CLI Reference

This document describes currently implemented command-line interfaces.

## `arlen`

Usage:

```text
arlen <command> [options]
```

Commands:

### `arlen new <AppName> [--full|--lite] [--force]`

Create a new app scaffold.

- `--full`: full app scaffold (default)
- `--lite`: single-file lite scaffold
- `--force`: overwrite existing files where allowed
- `--help` / `-h`: show command usage

### `arlen generate <controller|endpoint|model|migration|test|plugin> <Name> [options]`

Generate app artifacts.

Common generator options (`controller` and `endpoint`):

- `--route <path>`: wire route into `src/main.m` or `app_lite.m`
- `--method <HTTP>`: route method override (default `GET`)
- `--action <name>`: generated action method name (default `index`)
- `--template [<logical_template>]`: create template + render stub
- `--api`: generate JSON-oriented endpoint action

Plugin generator options:

- `--preset <generic|redis-cache|queue-jobs|smtp-mail>`: choose service-oriented plugin scaffold (default `generic`)

Generator behavior:

- `controller`: `src/Controllers/<Name>Controller.{h,m}`
- `endpoint`: same controller output with endpoint-oriented defaults (`--route` required)
- `model`: `src/Models/<Name>Repository.{h,m}`
- `migration`: `db/migrations/<timestamp>_<name>.sql`
- `test`: `tests/<Name>Tests.m`
- `plugin`: `src/Plugins/<Name>Plugin.{h,m}` and class auto-registration in `config/app.plist` (`plugins.classes`), with optional `--preset` service templates

Notes:

- placeholder routes are supported (for example `/user/admin/:id`)
- endpoint generator can create route + action + optional template in one command

### `arlen migrate [--env <name>] [--dsn <connection_string>] [--dry-run]`

Apply SQL migrations from `db/migrations` to PostgreSQL.

- `--env <name>`: select runtime environment (default: `development`)
- `--dsn <connection_string>`: override config DSN
- `--dry-run`: list pending migrations without applying

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

### `arlen check`

Run full quality gate (`make check`):

- unit tests
- integration tests
- perf gate

### `arlen build`

Build framework targets (`make all`).

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
- built-in observability/API docs endpoints are available when enabled:
  - `/metrics`
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
- `--no-respawn`

Signals:

- `TERM` / `INT`: graceful shutdown
- `HUP`: rolling worker reload

## Other Helper Scripts and Build Targets

- `bin/test`: run test suite (`make test`)
- `bin/tech-demo`: run technology demo app
- `bin/dev`: alias for `bin/boomhauer`
- `make ci-quality`: run unit + integration + multi-profile perf quality gate
- `make deploy-smoke`: validate deployment runbook with automated release smoke
- `make docs-html`: generate browser-friendly docs under `build/docs`

## PostgreSQL Test Gate

DB-backed tests are skipped unless this environment variable is set:

- `ARLEN_PG_TEST_DSN`: PostgreSQL connection string for migration/adapter tests
