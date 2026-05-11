# Arlen Phase 1 Specification

Status: Draft  
Last updated: 2026-02-19

## 1. Purpose

Phase 1 delivers a production-usable, bare-bones MVC framework for GNUstep/Objective-C applications.

The intent is not to clone Mojolicious internals. The intent is to solve similar web-application problems while staying fully aligned with Objective-C/GNUstep conventions and strengths:

- Foundation-first APIs
- Objective-C class/protocol design
- `NSError **` error propagation
- deterministic build and runtime behavior
- strong testability and measurable performance

## 2. Design Principles

1. GNUstep-native, not language-agnostic.
2. Prefer existing GNUstep Foundation/libs-base functionality over custom framework primitives.
3. Keep HTTP scope explicit: HTTPS is out of scope in framework runtime.
4. Make performance visible with built-in instrumentation and benchmark gates.
5. Keep Phase 1 small enough to ship and reliable enough to host real apps.
6. Default-first developer experience: optimize for simple apps first, advanced customization second.

## 2.1 Developer Experience Goal

Arlen should be dead simple for application developers to use.

Primary product goal:

- 80-90% of applications should run on rational framework defaults without needing internal framework changes.
- Advanced behavior should be available through explicit extension points (subclassing, middleware, hooks, custom config), not by rewriting runtime internals.

This follows the same high-level philosophy used by frameworks like Mojolicious:

- strong conventions and sane defaults for common use cases
- progressive disclosure for advanced capabilities

Phase 1 expectations for this goal:

1. A minimal app should only require route/controller/template intent and a concise startup entrypoint.
2. HTTP server internals (socket loop, parse limits, signal handling, proxy plumbing) should live in framework code, not normal app code.
3. CLI and generated app scaffolds should prefer defaults, avoid verbose configuration, and minimize manual wiring for common endpoint flows.

## 3. Phase 1 Scope

### In Scope

- HTTP/1.1 plaintext app server.
- Router with method + path matching and path parameters.
- Controller/action dispatch model.
- `arlen` CLI for app generation, dev run, test, and diagnostics.
- Full app mode as default application style.
- Lite app mode as optional single-file syntax sugar over the same runtime.
- View rendering via EOC (`.html.eoc`) templates.
- Partial include support via template registry.
- Request/response/context abstractions.
- Config loading with environment overlays.
- Structured logging and request timing metrics.
- Unit, integration, and performance test suites.
- Developer server workflow for local iteration.
- Reverse-proxy deployment model (nginx/apache/Caddy in front).

### Explicitly Out of Scope

- HTTPS/TLS termination inside framework runtime.
- WebSockets, SSE, HTTP/2.
- Prefork worker manager (`propane`) and its configuration surface ("propane accessories").
- Built-in ORM as a core dependency.
- Distributed session stores.
- Job queue framework.
- Auto-scaling orchestration.

## 4. High-Level Architecture

### 4.1 Subsystems

- `src/Arlen/Core/`
  - application bootstrap
  - environment/config resolution
  - service container/registry
- `src/Arlen/HTTP/`
  - socket listener
  - request parsing
  - response serialization
- `src/Arlen/MVC/Routing/`
  - route table
  - method/path matcher
  - route param extraction
- `src/Arlen/MVC/Controller/`
  - base controller helpers
  - action dispatch
- `src/Arlen/MVC/View/`
  - view lookup
  - render orchestration
- `src/Arlen/MVC/Template/`
  - EOC transpiler/runtime (already bootstrapped)
- `src/Arlen/Support/`
  - logging, metrics, utility helpers

### 4.2 Core Runtime Types

- `ALNApplication`
  - owns server, router, config, middleware chain
- `ALNRequest`
  - immutable request model
- `ALNResponse`
  - mutable response builder
- `ALNContext`
  - request-scoped object with request/response params/stash/logger/metrics
- `ALNRouter`
  - route registration and matching
- `ALNController`
  - base class with render helpers

## 5. HTTP and Networking

### 5.1 Protocol Support

- HTTP/1.1 only.
- Keep-alive optional in Phase 1 (default off if complexity impacts reliability).
- Bind defaults to `127.0.0.1` for dev safety.

### 5.2 Reverse Proxy Model

- Framework handles plaintext HTTP on loopback/private network.
- TLS termination and public ingress are delegated to nginx/apache/Caddy.
- Proxy headers (`X-Forwarded-For`, `X-Forwarded-Proto`) parsed only when trusted proxy mode is enabled.

### 5.3 Request Limits

- Configurable max request line, header bytes, and body size.
- Over-limit responses:
  - `413 Payload Too Large`
  - `431 Request Header Fields Too Large`

## 6. Routing

### 6.1 Route Features

- method + path route registration
- path parameter extraction (`/users/:id`)
- mixed static/dynamic path patterns such as `/user/admin/:id`
- wildcard tail (`/assets/*path`) optional in Phase 1
- named routes for URL generation
- route parameters exposed to actions via `ctx.params` and controller param helpers

### 6.2 Route Priority

Order:
1. static exact routes
2. parameterized routes
3. wildcard routes

If tie remains, first registration wins.

### 6.3 Controller Binding

Route target convention:

- `ControllerClass#actionMethod`

Example:

- `GET /users/:id -> UsersController#show`

## 7. Controller and View Behavior

### 7.1 Controller Contract

Recommended action signature:

```objc
- (id)show:(ALNContext *)ctx;
```

Action responsibilities:

- read request/route/query/body inputs from `ctx`
- call domain/repository services
- set response via helper methods
- optionally return an object for implicit response handling

### 7.2 Render Helpers

Minimum Phase 1 helpers:

- `renderTemplate:@"users/show" context:...`
- `renderJSON:object`
- `renderText:string`
- `redirectTo:status:`
- `setStatus:`

Ergonomic follow-on contract (Phase 2D, non-breaking addition; now implemented):

- add concise render defaults for common HTML responses (`render` / `render:locals:` style helper family)
- keep explicit helpers above as stable escape hatches for advanced behavior
- add controller-local/stash convenience helpers so common templates require minimal controller boilerplate

Controller class JSON options:

- `+ (NSJSONWritingOptions)jsonWritingOptions;`
- default returns `0`
- subclasses may override (for example pretty-print in development)

### 7.3 EOC Template Lookup

Convention:

- logical template `users/show` -> `templates/users/show.html.eoc`

Partials:

- `templates/partials/_nav.html.eoc`

Layouts:

- supported in simple form in Phase 1
- explicit render option rather than implicit global magic

### 7.4 Escaping Rules

- `<%= ... %>` escapes HTML by default.
- `<%== ... %>` bypasses escaping.
- template code is trusted code in Phase 1.

### 7.5 Implicit JSON Response Behavior

If an action returns `NSDictionary` or `NSArray`, and no explicit render/redirect has already been performed, framework behavior is:

1. serialize return value with `NSJSONSerialization`
2. use `+[ControllerClass jsonWritingOptions]`
3. set `Content-Type: application/json; charset=utf-8`
4. set status `200` if status is unset
5. write serialized JSON response body

Failure behavior:

- JSON serialization failure returns `500`
- error is logged with controller/action context and request id

Guardrails:

- Implicit JSON is limited to `NSDictionary` and `NSArray` in Phase 1.
- Scalar/object implicit serialization is out of scope in Phase 1.
- explicit `renderJSON:` always takes precedence over implicit behavior.

## 8. Configuration

### 8.1 Files

- `config/app.plist`
- `config/environments/development.plist`
- `config/environments/test.plist`
- `config/environments/production.plist`

Load order:
1. `app.plist`
2. environment file
3. environment variables

### 8.2 Required Settings

- bind host
- port
- environment
- logging format
- request size limits
- trusted proxy mode
- performance logging enable/disable

## 9. Logging and Error Handling

### 9.1 Error Conventions

- Foundation-style errors with `NSError **`.
- domain names by subsystem:
  - `Arlen.HTTP.Error`
  - `Arlen.Routing.Error`
  - `Arlen.Controller.Error`
  - `Arlen.EOC.Error`

### 9.2 Request Logging

Per-request log includes:

- request id
- method
- path
- status
- total duration
- route/controller action

Logging formats:

- text (dev)
- JSON lines (prod/test/perf)

## 10. Performance Architecture

Performance is a first-class Phase 1 feature, not deferred work.

### 10.1 Built-In Timers

Track and emit stage timings:

- request parse
- route match
- controller execution
- view/template render
- response write
- total request

### 10.2 Metrics Export

Phase 1 output targets:

- console summary
- JSON report file under `build/perf/`
- optional CSV for external analysis

### 10.3 Benchmark Suite

Add `tests/performance/` with repeatable scenarios:

- trivial text endpoint
- routed controller endpoint
- EOC rendered endpoint
- endpoint with partial include

Benchmark output fields:

- requests/sec
- p50/p95/p99 latency
- max latency
- error rate
- memory snapshot before/after run

### 10.4 Regression Gate

Default gate in CI/local perf target:

- fail when p95 latency regresses by >15% against baseline profile under identical scenario

Baseline files:

- `tests/performance/baselines/*.json`

## 11. Testing Strategy

### 11.1 Unit Tests

- parser/tokenizer/transpiler correctness
- router matching and precedence
- controller helper behavior
- config merge logic

### 11.2 Integration Tests

- start server on ephemeral port
- exercise HTTP endpoints
- assert status, headers, body, and content type
- assert template rendering and escaping

### 11.3 Performance Tests

- controlled warm-up
- fixed iteration counts
- deterministic scenario scripts
- machine metadata captured in report for traceability

### 11.4 Test Runner Standard

- `tools-xctest`/`xctest` as canonical test framework runner
- GNUstep environment initialization required before test execution

## 12. Build and Development Workflow

### 12.1 Build Pipeline

1. transpile templates (`eocc`)
2. compile generated sources
3. compile runtime/app components
4. build CLI (`arlen`)
5. run unit/integration tests
6. run performance suite

`arlen` is the standard developer entry point for generating and running full/lite applications.

### 12.2 Dev Server

Phase 1 target:

- single-process developer server (`boomhauer`)
- direct `boomhauer` CLI workflow from app root
- default watch mode to restart/recompile on source/template/config/public changes
- should prioritize reliability over ultra-fast reload

### 12.3 Server Naming Convention

- Development server name: `boomhauer`.
- Production process manager name (Phase 2): `propane`.
- All `propane` configuration settings and grouped config sections must be referred to as "propane accessories".

### 12.4 Boilerplate Reduction Contract (Phase 2D, Implemented)

To keep Arlen default-first and competitive on developer ergonomics, app scaffolding work meets:

1. Generated full/lite entrypoints delegate argument parsing and server boot wiring to framework runner APIs (`ALNRunAppMain`), without duplicating logic in each app.
2. Common endpoint additions do not require manual edits to runtime boot plumbing (`main.m`/`app_lite.m`) when generator route-wiring options are used.
3. Route placeholder patterns (for example `/user/admin/:id`) remain first-class in concise route declaration APIs.
4. Controller happy-path HTML rendering is available with minimal boilerplate while preserving explicit APIs for advanced/error-sensitive cases.

## 13. Data Layer Policy (Phase 1)

No framework-mandated ORM in Phase 1.

Provide repository-oriented abstraction points:

- protocol-based repositories
- transaction boundary hooks
- clear service injection points in controllers

This keeps persistence flexible and allows Phase 2 modules such as:

- `ArlenPg` analog to `Mojo::Pg`
- optional GDL2 integration module
- optional custom ORM experiments behind stable interfaces

## 14. Security Posture (Phase 1)

- Trusted templates.
- TLS out of framework scope.
- header/body size limits enforced.
- safe HTML escaping default in templates.
- explicit raw HTML output only with `<%== ... %>`.
- no claim of sandboxing or untrusted code execution.

## 15. Deliverables

Phase 1 is complete when the following are true:

1. A multi-route MVC app can run and serve responses over HTTP.
2. Controller actions can render EOC templates and JSON.
3. App runs behind reverse proxy in plaintext mode.
4. Unit/integration suites pass in CI.
5. Performance suite emits stable reports and enforces regression gate.
6. Developer workflow supports local iteration with a dev server.

## 16. Recommended Milestone Sequence

1. Router + request/response/context core.
2. Controller dispatch and helper API.
3. View resolver + EOC integration with layout support.
4. Config loader + environment overlays.
5. Structured logging + request timing.
6. Integration test harness.
7. Performance benchmark suite + regression gate.
8. Documentation and example app hardening.

## 17. Key Decision Points Requiring Confirmation

1. Concurrency model in Phase 1
   - Recommendation: single process + bounded thread pool.
   - Rationale: better throughput than strict single-thread while keeping complexity lower than prefork/event-loop architecture.

2. Dev reload model
   - Recommendation: full process restart on source/template/config changes.
   - Rationale: most reliable behavior for Objective-C runtime and generated code updates.

3. Session support in Phase 1
   - Recommendation: signed cookie session only, no server-side store.
   - Rationale: minimal operational complexity while supporting common auth flow prototypes.

4. Static assets in Phase 1
   - Recommendation: framework serves static assets in development only; production delegated to reverse proxy.
   - Rationale: keeps core focused and avoids duplicate static serving optimizations.

5. Logging default format
   - Recommendation: text in development, JSON lines in test/production.
   - Rationale: readable local logs plus machine-friendly structured logs for automation.

6. Phase 1 persistence stance
   - Recommendation: repository protocols only; postpone ORM decision to Phase 2.
   - Rationale: preserves flexibility for GDL2, ArlenPg, or custom ORM without core churn.

7. Performance gate strictness
   - Recommendation: fail when p95 regresses by >15% in controlled perf suite.
   - Rationale: meaningful guardrail that catches real regressions while avoiding noise.

8. Boilerplate reduction scope and timing
   - Recommendation: implement one-line entrypoint/run wiring, route-generation ergonomics, and concise render helper defaults in Phase 2D as additive APIs.
   - Rationale: improves onboarding and day-to-day productivity without sacrificing explicit low-level control.
