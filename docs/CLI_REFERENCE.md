# CLI Reference

This document describes the currently implemented command-line interfaces.

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

### `arlen generate <controller|model|migration|test> <Name>`

Generate app artifacts.

- `controller`: `src/Controllers/<Name>Controller.{h,m}`
- `model`: `src/Models/<Name>Repository.{h,m}`
- `migration`: `db/migrations/<timestamp>_<name>.sql`
- `test`: `tests/<Name>Tests.m`
- `--help` / `-h`: show command usage

### `arlen migrate [--env <name>] [--dsn <connection_string>] [--dry-run]`

Apply SQL migrations from `db/migrations` to PostgreSQL.

- `--env <name>`: select runtime environment (default: `development`)
- `--dsn <connection_string>`: override `database.connectionString` from config
- `--dry-run`: list pending migrations without applying

### `arlen boomhauer [server args...]`

Build and run `boomhauer` for the current app root.

- delegates to `bin/boomhauer` with `ARLEN_APP_ROOT` + `ARLEN_FRAMEWORK_ROOT`
- defaults to watch mode (same behavior as running `bin/boomhauer` directly)
- in app-root watch mode, transpile/compile failures do not terminate `boomhauer`; a diagnostic server is served until the next successful rebuild
- server args are passed through (for example `--watch`, `--no-watch`, `--prepare-only`, `--port`, `--host`, `--env`, `--once`, `--print-routes`)

### `arlen propane [manager args...]`

Run the production manager (`propane`) for the current app root.

- manager args are forwarded to `bin/propane`
- all production manager settings are called "propane accessories"

### `arlen routes`

Build app and print resolved routes (`--print-routes`).

### `arlen test [--unit|--integration|--all]`

Run framework tests.

- default: equivalent to `--all`

### `arlen perf`

Run performance suite.

### `arlen build`

Build framework targets (`make all`).

### `arlen config [--env <name>] [--json]`

Load and print merged runtime config.

- `--env <name>`: select environment overlay
- `--json`: print as pretty JSON

## `boomhauer` Script (`bin/boomhauer`)

Usage:

```text
boomhauer [options]
```

Behavior:
- If run inside an app root (`config/app.plist` plus `src/main.m` or `app_lite.m`), it compiles that app and watches for changes by default.
- Otherwise, it runs the framework's built-in server.
- In app-root watch mode, build failures are captured and rendered as development diagnostics:
  - browser requests receive an HTML build-error page
  - API requests can use `GET /api/dev/build-error` for JSON diagnostics
  - successful source changes automatically resume normal app serving

Options:
- `--watch` (default)
- `--no-watch`
- `--once`
- `--prepare-only` (compile and exit)
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
- `make docs-html`: generate browser-friendly HTML docs under `build/docs`

## PostgreSQL Test Gate

DB-backed tests are skipped unless this environment variable is set:

- `ARLEN_PG_TEST_DSN`: PostgreSQL connection string for migration/adapter tests
