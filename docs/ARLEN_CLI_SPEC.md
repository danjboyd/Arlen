# Arlen CLI Specification

Status: Implemented through Phase 29L  
Last updated: 2026-04-07

## 1. Purpose

`arlen` is the canonical command-line interface for Arlen.

It standardizes workflows for:

- creating apps
- generating framework artifacts
- running development and production servers
- running tests/perf quality gates
- inspecting routes/config
- applying DB migrations
- generating typed DB schema helper APIs

## 2. Design Goals

1. Full app mode is the default path.
2. Command behavior is deterministic and scriptable.
3. Generated apps run with minimal edits.
4. Common endpoint workflows avoid manual boot plumbing edits.
5. Full and lite modes share runtime behavior and tool entry points.

## 3. Command Structure

```text
arlen <command> [subcommand] [options]
```

Implemented command groups:

- `new`
- `generate`
- `boomhauer`
- `propane`
- `deploy`
- `migrate`
- `schema-codegen`
- `typed-sql-codegen`
- `routes`
- `test`
- `perf`
- `check`
- `build`
- `config`
- `doctor`

## 4. Command Contracts

### 4.1 `arlen new <AppName> [--full|--lite] [--force]`

- default scaffold mode: full
- full and lite entrypoints use `ALNRunAppMain(...)`
- generated full scaffold defaults to EOC sigil-local rendering (`<%= $title %>`)

### 4.2 `arlen generate <type> <Name> [options]`

Types:

- `controller`
- `endpoint`
- `model`
- `migration`
- `test`

Controller/endpoint options:

- `--route <path>`
- `--method <HTTP>`
- `--action <name>`
- `--template [<logical_template>]`
- `--api`

Behavior:

- route placeholders are supported (for example `/user/admin/:id`)
- if `--route` is provided, route registration is auto-wired into `src/main.m` or `app_lite.m`
- endpoint generator can scaffold route + controller action + optional template in one command

### 4.3 `arlen boomhauer [server args...]`

- runs framework `bin/boomhauer` with app/framework roots resolved
- defaults to watch-mode behavior from `boomhauer`
- forwards server args (for example `--port`, `--host`, `--env`, `--watch`, `--no-watch`, `--once`, `--print-routes`)

### 4.4 `arlen propane [manager args...]`

- runs framework `bin/propane`
- all production manager settings are referred to as "propane accessories"

### 4.5 `arlen migrate [--env <name>] [--database <target>] [--dsn <connection_string>] [--dry-run]`

- applies SQL migrations from `db/migrations` (`db/migrations/<target>` for non-default targets)
- resolves DSN from `--dsn`, `ARLEN_DATABASE_URL_<TARGET>`, `ARLEN_DATABASE_URL`, or config `database/databases`
- migration state table is target-aware (`arlen_schema_migrations` or `arlen_schema_migrations__<target>`)

### 4.5A `arlen deploy <list|dryrun|init|push|releases|release|status|rollback|doctor|logs> [options]`

- `list` reports configured deploy targets from `config/deploy.plist`
- `dryrun` validates release packaging inputs and emits a stable deploy planning payload
- `plan` remains a deprecated compatibility alias for `dryrun`
- `push` builds a local immutable release artifact under `releases/<release-id>/`
- `push` writes `metadata/manifest.json` using contract version `phase32-deploy-manifest-v1`
- `releases` reports release artifacts available to activate
- deploy manifests now carry target-aware deployment metadata (`local_profile`,
  `target_profile`, `runtime_strategy`, `support_level`,
  `compatibility_reason`, and remote rebuild requirements)
- deploy manifests now also carry a `propane_handoff` contract describing the
  packaged `propane` / `jobs-worker` paths, `release.env`, the
  `propaneAccessories` config key, and the default deploy runtime action
- `release` reuses or creates the selected release, runs migrations when packaged `.sql` files exist, and activates `releases/current`
- `release` can optionally verify `GET /healthz` through `--base-url <url>`
- `release` fails closed when the packaged manifest records an unsupported
  target profile
- `release` requires `--remote-build-check-command <shell>` to succeed when
  the packaged manifest records an experimental remote rebuild target
- operability endpoints used by deploy verification are reserved ahead of app routes
- `status` reports the active release, previous release, manifest-backed health contract, and optional service state
- `status` now also reports deployment metadata for the active release and
  rollback candidate
- `status` now reports the packaged `propane_handoff` contract for the active
  release and rollback candidate
- `rollback` promotes a previous release through `rollback_release.sh`, can reload/restart a service, and can re-run deploy health verification
- `rollback` now reports deployment metadata for the rollback source and
  activated target
- `rollback` now reports the packaged `propane_handoff` contract for the
  rollback source and activated target
- `doctor` validates active release layout, packaged binaries, config loading, and optional live operability
- `doctor` also validates deployment compatibility metadata and requires a
  remote build-check command for experimental remote rebuild targets
- `doctor` reports the packaged `propane_handoff` contract in JSON mode
- packaged releases include the operability helper `framework/tools/deploy/validate_operability.sh` used by `doctor --base-url`
- `logs` exposes release metadata pointers plus journald/file log access helpers
- shared options:
  - `--app-root <path>`
  - `--framework-root <path>`
  - `--releases-dir <path>`
  - `--release-id <id>`
  - `--target-profile <profile>`
  - `--runtime-strategy <system|managed|bundled>`
  - `--allow-remote-rebuild`
  - `--remote-build-check-command <shell>`
  - `--service <name>`
  - `--certification-manifest <path>`
  - `--json-performance-manifest <path>`
  - `--allow-missing-certification`
  - `--json`
  - `--env <name>` and `--base-url <url>` for runtime-aware subcommands
  - `--runtime-action <reload|restart|none>` for `release` and `rollback`
  - `--lines <count>`, `--follow`, and `--file <path>` for `logs`

### 4.6 `arlen routes`

- builds and prints resolved route table (`--print-routes` path)

### 4.7 `arlen test [--unit|--integration|--all]`

- default: equivalent to `--all`

### 4.8 `arlen perf`

- runs perf suite and gate (`make perf`)
- emits reports in `build/perf/`

### 4.9 `arlen check`

- runs unified quality gate (`make check`)
- includes unit + integration + perf gate

### 4.10 `arlen build`

- builds framework targets (`make all`)

### 4.11 `arlen config [--env <name>] [--json]`

- prints merged runtime config for selected environment

### 4.12 `arlen doctor [--env <name>] [--json]`

- runs bootstrap diagnostics before any framework build requirement
- supports machine-readable output for onboarding and CI gating

### 4.13 `arlen schema-codegen [--env <name>] [--database <target>] [--dsn <connection_string>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--typed-contracts] [--force]`

- introspects PostgreSQL `information_schema` for non-system schemas
- emits deterministic typed helper artifacts (`<prefix>Schema.h/.m`) and JSON manifest
- supports overwrite via `--force` for regeneration workflows
- optional typed table contracts via `--typed-contracts` (row/insert/update + decode helpers)
- non-default targets use deterministic defaults when not overridden:
  - output dir: `src/Generated/<target>`
  - manifest: `db/schema/arlen_schema_<target>.json`
  - prefix: `ALNDB<PascalTarget>`
  - manifest metadata includes `"database_target"`

### 4.14 `arlen typed-sql-codegen [--input-dir <path>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--force]`

- compiles SQL files with `-- arlen:name|params|result` metadata into typed parameter/result helpers
- default input directory: `db/sql/typed`
- emits deterministic generated artifacts:
  - `<output-dir>/<prefix>TypedSQL.h`
  - `<output-dir>/<prefix>TypedSQL.m`
  - `<manifest>` (default `db/schema/arlen_typed_sql.json`)

## 5. Project Awareness

`arlen` operates in two modes:

1. Outside app root: `new`
2. Inside app root: run/generate/build/test/perf/check/routes/config/deploy/migrate/schema-codegen/typed-sql-codegen

Framework root resolution order:

1. `ARLEN_FRAMEWORK_ROOT`
2. parent-directory discovery
3. inference from `arlen` executable location

## 6. Full vs Lite Contract

- full mode remains default
- lite mode is opt-in (`--lite`)
- both modes share the same runtime/rendering stack
- both modes use the same runner entrypoint contract

## 7. Exit Codes

- `0`: success
- `1`: runtime/build/test/perf failure
- `2`: usage/argument error

## 8. Near-Term Additions

- `deploy init` as a narrow, optional host bootstrap helper after the core deploy product stabilizes
- target-aware deploy configuration and platform-profile validation for
  production targets
- richer `deploy doctor` target probes for runtime strategy, host readiness,
  declared database mode, required env key presence, runtime-root conflicts,
  and explicit remote rebuild gating
- richer generator extension hooks
- plugin/lifecycle scaffolding commands
