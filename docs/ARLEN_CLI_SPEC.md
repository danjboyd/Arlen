# Arlen CLI Specification

Status: Implemented through Phase 4C  
Last updated: 2026-02-20

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
- `migrate`
- `schema-codegen`
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

### 4.5 `arlen migrate [--env <name>] [--dsn <connection_string>] [--dry-run]`

- applies SQL migrations from `db/migrations`
- resolves DSN from `--dsn`, `ARLEN_DATABASE_URL`, or config `database.connectionString`

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

### 4.13 `arlen schema-codegen [--env <name>] [--dsn <connection_string>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--force]`

- introspects PostgreSQL `information_schema` for non-system schemas
- emits deterministic typed helper artifacts (`<prefix>Schema.h/.m`) and JSON manifest
- supports overwrite via `--force` for regeneration workflows

## 5. Project Awareness

`arlen` operates in two modes:

1. Outside app root: `new`
2. Inside app root: run/generate/build/test/perf/check/routes/config/migrate/schema-codegen

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

## 8. Near-Term Additions (Phase 3)

- deployment-oriented CLI helpers layered on existing `tools/deploy/*` scripts
- richer generator extension hooks
- plugin/lifecycle scaffolding commands
