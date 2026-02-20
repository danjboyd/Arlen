# Core Concepts

This guide explains Arlen's runtime model at a high level.

## 1. Request Lifecycle

1. `ALNHTTPServer` accepts an HTTP request.
2. Request is parsed into `ALNRequest`.
3. `ALNRouter` matches method/path to a route.
4. `ALNApplication` handles built-ins (`/healthz`, `/readyz`, `/livez`, `/metrics`, `/clusterz`, OpenAPI/docs paths) when no app route matches.
5. Request contract coercion/validation runs (if configured on the matched route).
6. Middleware and auth scope/role checks run.
7. Controller action executes.
8. Controller writes response directly or returns `NSDictionary`/`NSArray` for implicit JSON.
9. Response contract validation runs (if configured), then metrics/perf/trace data are finalized.
10. `ALNResponse` is serialized and sent.

## 2. Core Types

- `ALNApplication`: app composition root; owns routes, config, middleware.
- `ALNHTTPServer`: network loop and request handling.
- `ALNRouter` / `ALNRoute`: route registration and matching.
- `ALNController`: base controller with render helpers.
- `ALNContext`: request-scoped object (`request`, `response`, `params`, `stash`, logging/perf references, validated params/auth/page-state helpers).
- `ALNRequest`: parsed request model.
- `ALNResponse`: mutable response builder.

## 3. EOC Templates

Template extension:
- `.html.eoc`

Supported tags:
- `<% code %>`: Objective-C statements
- `<%= expr %>`: HTML-escaped expression output
- `<%== expr %>`: raw expression output
- `<%# comment %>`: ignored template comment

Transpiler/runtime:
- `tools/eocc` transpiles templates to Objective-C source.
- `ALNEOCRuntime` provides rendering and include support.

## 4. Data Layer Model

- `ALNPg`: default PostgreSQL adapter and raw-SQL execution path.
- `ALNDatabaseAdapter` / `ALNDatabaseConnection`: adapter protocol used for conformance and optional compatibility layers.
- `ALNSQLBuilder`: optional SQL construction helper (v2 supports nested predicates, joins/aliases, CTE/subquery composition, grouping/having, and `RETURNING`).
- `ALNPostgresSQLBuilder`: explicit PostgreSQL dialect extension layer for `ON CONFLICT`/upsert semantics.
- `ALNDisplayGroup`: optional sort/filter/batch data-controller helper on top of adapters.
- `ALNGDL2Adapter`: optional migration-oriented adapter wrapper for GDL2/EOControl compatibility paths.
- `ArlenData` umbrella (`src/ArlenData/ArlenData.h`): data-layer-only packaging surface for non-Arlen projects.

## 5. JSON Response Behavior

If controller action returns an `NSDictionary` or `NSArray` and no explicit body has been committed:
- Arlen serializes it to JSON implicitly.
- `Content-Type` is set to `application/json; charset=utf-8`.
- Controller class may override JSON options via `+jsonWritingOptions`.

## 6. API Contracts and OpenAPI Docs

- Request/response contracts can be configured per route for deterministic validation/coercion.
- OpenAPI JSON endpoints:
  - `/openapi.json`
  - `/.well-known/openapi.json`
- Documentation endpoints:
  - `/openapi` (interactive explorer by default)
  - `/openapi/viewer` (lightweight fallback)
  - `/openapi/swagger` (self-hosted swagger-style docs UI)
- `openapi.docsUIStyle` controls `/openapi` rendering (`interactive`, `viewer`, or `swagger`).

## 7. Realtime and Composition

- WebSocket controller contracts:
  - `acceptWebSocketEcho`
  - `acceptWebSocketChannel:`
- SSE controller contract:
  - `renderSSEEvents:`
- Realtime channel fanout abstraction:
  - `ALNRealtimeHub`
- App composition:
  - `mountApplication:atPrefix:`
  - mounted requests are path-rewritten and dispatched into child app context.

Cluster runtime contract (Phase 3H):

- `GET /clusterz` returns runtime cluster identity and deployment contract details.
- Responses include `X-Arlen-Cluster`, `X-Arlen-Node`, and `X-Arlen-Worker-Pid` when `cluster.emitHeaders = YES`.
- Session mode is signed-cookie payloads; multi-node deployments must share `session.secret` across nodes.
- Realtime fanout remains node-local by default (`ALNRealtimeHub`); multi-node broadcast requires an external broker layer.

## 8. Ecosystem Services

Arlen Phase 3E adds plugin-first ecosystem service adapters:

- jobs: `ALNJobAdapter`
- cache: `ALNCacheAdapter`
- i18n: `ALNLocalizationAdapter`
- mail: `ALNMailAdapter`
- attachments: `ALNAttachmentAdapter`

Default in-memory adapters are provided and can be replaced by plugins during app registration.
Concrete backend adapters available: `ALNRedisCacheAdapter`, `ALNFileSystemAttachmentAdapter`.

Controller-level service access is available through `ALNController`/`ALNContext` helpers:

- `jobsAdapter`
- `cacheAdapter`
- `localizationAdapter`
- `mailAdapter`
- `attachmentAdapter`
- `localizedStringForKey:locale:fallbackLocale:defaultValue:arguments:`

Optional job runtime contract for scheduled/asynchronous execution:

- `ALNJobWorkerRuntime`
- `ALNJobWorker`
- `ALNJobWorkerRunSummary`

## 9. Compatibility Helpers

- `compatibility.pageStateEnabled` enables session-backed page-state behavior for migration scenarios.
- Default remains stateless/transient page-state behavior unless explicitly enabled.

## 10. Configuration Model

Config is loaded from:
- `config/app.plist`
- `config/environments/<environment>.plist`

Environment variables may override key values (`ARLEN_*`).

## 11. Development vs Production Naming

- Development server: `boomhauer`
- Production process manager: `propane`
- `propane` config is called "propane accessories"
