# Arlen CLI Specification (Phase 1)

Status: Draft  
Last updated: 2026-02-18

## 1. Purpose

`arlen` is the canonical command-line interface for Arlen.

It standardizes developer workflows for:

- creating applications
- generating framework artifacts
- running the development server (`boomhauer`)
- running tests and performance checks
- inspecting routes/config

## 2. Design Goals

1. Make full app mode the default path.
2. Keep command behavior deterministic and scriptable.
3. Reuse framework runtime/build tools instead of duplicating logic in shell scripts.
4. Provide a lightweight onboarding path for new users.
5. Default-first developer experience: generated apps should run on sane defaults with minimal code.
6. Foundation/libs-base-first implementation: avoid re-implementing functionality available in GNUstep libs-base unless the existing behavior is too heavy or misaligned with project goals.

## 2.1 Developer Experience Guardrails

- `arlen new` should generate an app scaffold that can run with minimal edits.
- `arlen boomhauer` should prefer convention defaults (`development`, configured host/port) and require no extra options for common workflows.
- Generated skeletons should keep HTTP/runtime internals in framework code, not app entrypoints.
- Advanced options should be opt-in and additive, not required for baseline usage.

## 3. Command Structure

```text
arlen <command> [subcommand] [options]
```

Core command groups:

- `new`
- `generate`
- `boomhauer`
- `routes`
- `test`
- `perf`
- `build`
- `config`

## 4. Phase 1 Commands

### 4.1 `arlen new`

Create a new application.

Default behavior:

- `arlen new MyApp` creates a full app skeleton.

Options:

- `--full` explicitly request full app skeleton.
- `--lite` create a single-file lite app scaffold.
- `--force` overwrite existing target directory.
- `--template <name>` optional starter variation.

### 4.2 `arlen generate`

Scaffold framework components inside an app.

Phase 1 generators:

- `controller <Name>`
- `model <Name>` (repository-oriented skeleton, not ORM-dependent)
- `migration <Name>` (placeholder format; db-specific execution may be Phase 2)
- `test <Name>`

### 4.3 `arlen boomhauer`

Run the development server.

Options:

- `--port <n>`
- `--host <addr>`
- `--watch` (restart on source/template/config changes)
- `--env <environment>`

Behavior:

- builds/transpiles as needed before launch
- runs app in development profile by default

### 4.4 `arlen routes`

Print resolved route table in registration order and priority resolution details.

Output fields:

- method
- path pattern
- target controller/action
- route name (if any)

### 4.5 `arlen test`

Run test suites using GNUstep XCTest tooling.

Default:

- unit + integration tests

Options:

- `--unit`
- `--integration`
- `--all`

### 4.6 `arlen perf`

Run performance suite and emit benchmark artifacts.

Outputs:

- console summary
- JSON report under `build/perf/`
- optional CSV

### 4.7 `arlen build`

Compile app/runtime artifacts for the active environment.

### 4.8 `arlen config`

Inspect merged runtime configuration.

Options:

- `--env <environment>`
- `--json`

## 5. Project Awareness

`arlen` operates in two modes:

1. Outside app directory:
   - supports `arlen new`
2. Inside app directory:
   - supports build/run/generate/test/perf/routes/config

App root detection (Phase 1):

- presence of expected app manifest markers (to be defined in implementation)
- for app-run commands, resolve framework root by searching parent directories
- fallback to inferring framework root from the `arlen` executable location
- support explicit override via `ARLEN_FRAMEWORK_ROOT`

## 6. Full vs Lite Handling

- Full mode is default for `arlen new`.
- Lite mode is opt-in (`--lite`).
- Both modes must run on the same core runtime and rendering stack.
- `arlen boomhauer`, `arlen test`, and `arlen perf` must work for both.

## 7. Error Handling and Exit Codes

- `0` success
- `1` runtime/build/test failure
- `2` invalid CLI usage/arguments

All command failures should return concise actionable messages.

## 8. Non-Goals (Phase 1)

- Plugin marketplace management
- Remote deployment orchestration
- Production process manager command (`arlen propane`) implementation

## 9. Phase 2 Preview

Planned additions:

- `arlen propane` for production manager controls
- deployment helper commands
- richer generator templates and extension hooks
