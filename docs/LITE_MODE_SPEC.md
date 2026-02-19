# Lite Mode Specification (Phase 1)

Status: Draft  
Last updated: 2026-02-18

## 1. Purpose

Define a lightweight application mode ("lite") for rapid prototyping while keeping full app mode as the default for serious deployments.

Lite mode must not be a separate runtime.

## 2. Core Principle

Lite mode is syntax sugar over the same core components used by full applications:

- same HTTP stack
- same router
- same controller/response behavior
- same EOC rendering pipeline
- same middleware model

No divergence in runtime semantics between full and lite modes.

## 3. Positioning

- Full mode: default and recommended for production applications.
- Lite mode: quick prototypes, demos, docs snippets, and minimal internal tools.

## 4. File and Structure Model

Phase 1 lite app shape:

- one primary entry file (for example `app_lite.m`)
- optional `templates/` directory for `.html.eoc` files
- optional `config/` for overrides

Lite apps may remain single-file, but can grow into directories without changing runtime model.

## 5. Runtime Features Required in Lite Mode

1. Route definitions (method + path)
2. Handler execution with request context
3. Template rendering via EOC
4. Explicit and implicit JSON responses
5. Middleware registration
6. Boomhauer development server launch

## 6. JSON Behavior in Lite Mode

Must match full mode exactly:

- handler return `NSDictionary`/`NSArray` triggers implicit JSON response
- `Content-Type: application/json; charset=utf-8`
- status defaults to `200` unless set

No lite-specific JSON semantics.

## 7. Arlen Integration

Lite creation and operation:

- `arlen new MyApp --lite`
- `arlen boomhauer`
- `arlen test`
- `arlen perf`

All commands should work with minimal lite-specific branching.

## 8. Migration Path: Lite -> Full

Phase 1 must support straightforward migration:

1. `arlen generate` adds controller/model/test structure.
2. Route declarations move from inline style to full app structure.
3. Existing templates and middleware remain reusable.

Goal: no rewrite required, only structural refactor.

## 9. Limitations in Phase 1

- No separate optimization path for lite.
- No runtime behavior unavailable in full mode.
- Lite-specific DSL features should be minimal and explicit.

## 10. Non-Goals

- Supporting contradictory behavior between lite and full.
- Building a distinct "micro framework" product.

## 11. Acceptance Criteria

Lite mode is acceptable in Phase 1 when:

1. A one-file app can serve at least two routes.
2. EOC template rendering works.
3. Implicit JSON return behavior works.
4. Same tests for equivalent full-mode behavior pass.
5. App can be moved to full structure without runtime rewrites.
