# API Reference

This reference is generated from public headers exported by `src/Arlen/Arlen.h` and `src/ArlenData/ArlenData.h`.

Regenerate after public header changes:

```bash
python3 tools/docs/generate_api_reference.py
```

- Generated from source headers and metadata (deterministic output)
- Public headers: `38`
- Symbols: `61`
- Public methods: `403`
- Public properties: `147`

## API Surface Boundary

- `src/Arlen/Arlen.h` is the primary framework umbrella header.
- `src/ArlenData/ArlenData.h` is the standalone data-layer umbrella header.

## Symbol Index

### Core

- [ALNApplication](api/ALNApplication.md): Primary runtime container for route registration, middleware/plugins, service adapters, lifecycle hooks, and OpenAPI metadata.
- [ALNConfig](api/ALNConfig.md): Configuration loader that merges base + environment plist files into the runtime config dictionary.
- [ALNLifecycleHook](api/ALNLifecycleHook.md): Lifecycle callback protocol invoked around app startup and shutdown boundaries.
- [ALNMiddleware](api/ALNMiddleware.md): Middleware protocol for pre-dispatch and optional post-dispatch request processing.
- [ALNPlugin](api/ALNPlugin.md): Plugin protocol for declarative app extension (registration + optional middleware contribution).
- [ALNTraceExporter](api/ALNTraceExporter.md): Trace-export protocol used to publish structured request spans to external observability sinks.

### HTTP

- [ALNHTTPServer](api/ALNHTTPServer.md): HTTP server host that binds an `ALNApplication` to socket runtime and request loop execution.
- [ALNRequest](api/ALNRequest.md): Immutable HTTP request model containing method/path/query/headers/body and parsed parameter helpers.
- [ALNResponse](api/ALNResponse.md): Mutable HTTP response model for status, headers, and body serialization into wire-format bytes.

### MVC Controllers

- [ALNContext](api/ALNContext.md): Per-request execution context shared across middleware and controllers, including params/auth/session/services.
- [ALNController](api/ALNController.md): Base controller with template/JSON rendering, parameter helpers, auth/session helpers, and envelope conventions.
- [ALNPageState](api/ALNPageState.md): Page-state helper for namespaced key/value persistence across requests in compatibility workflows.

### MVC Routing

- [ALNRoute](api/ALNRoute.md): Single route descriptor containing method/path pattern/controller/action and matching helpers.
- [ALNRouteMatch](api/ALNRouteMatch.md): Route match result object containing matched route metadata and extracted route params.
- [ALNRouter](api/ALNRouter.md): Route registry and matcher with support for route grouping, guard actions, and format constraints.

### Middleware

- [ALNCSRFMiddleware](api/ALNCSRFMiddleware.md): CSRF validation middleware for state-changing requests using token headers/query params.
- [ALNRateLimitMiddleware](api/ALNRateLimitMiddleware.md): In-memory rate limiting middleware for per-window request throttling.
- [ALNResponseEnvelopeMiddleware](api/ALNResponseEnvelopeMiddleware.md): Middleware that normalizes JSON API responses into a consistent envelope shape.
- [ALNSecurityHeadersMiddleware](api/ALNSecurityHeadersMiddleware.md): Middleware that injects security-related response headers (including optional CSP).
- [ALNSessionMiddleware](api/ALNSessionMiddleware.md): Session middleware that signs/verifies cookie-backed session state for request context access.

### Template

- [ALNEOCTranspiler](api/ALNEOCTranspiler.md): EOC template compiler/transpiler with lint diagnostics and deterministic symbol/path resolution.

### View

- [ALNView](api/ALNView.md): Template renderer that executes transpiled EOC templates with optional strict locals/stringify behavior.

### Data

- [ALNDatabaseAdapter](api/ALNDatabaseAdapter.md): Database-adapter protocol defining connection lifecycle, query primitives, transactions, and capability metadata.
- [ALNDatabaseConnection](api/ALNDatabaseConnection.md): Database-connection protocol defining query/command primitives used by adapters and routers.
- [ALNDatabaseRouter](api/ALNDatabaseRouter.md): Read/write routing layer that selects database targets by operation class and routing context.
- [ALNDisplayGroup](api/ALNDisplayGroup.md): DisplayGroup-style query helper that builds list fetches from filter and sort descriptors.
- [ALNGDL2Adapter](api/ALNGDL2Adapter.md): Optional GDL2 compatibility adapter with fallback behavior when native GDL2 runtime is unavailable.
- [ALNMigrationRunner](api/ALNMigrationRunner.md): Migration discovery and migration execution runner for SQL migration directories.
- [ALNPg](api/ALNPg.md): PostgreSQL adapter with pooled connections and adapter-compatible query/command/transaction APIs.
- [ALNPgConnection](api/ALNPgConnection.md): PostgreSQL connection wrapper with SQL execution, prepared statements, transactions, and builder execution helpers.
- [ALNPostgresSQLBuilder](api/ALNPostgresSQLBuilder.md): PostgreSQL dialect extension for `ALNSQLBuilder` covering `ON CONFLICT` upsert behaviors.
- [ALNSQLBuilder](api/ALNSQLBuilder.md): Fluent SQL builder for `SELECT`/`INSERT`/`UPDATE`/`DELETE` with expression-safe composition and deterministic SQL output.
- [ALNSchemaCodegen](api/ALNSchemaCodegen.md): Schema artifact generator for typed table/column contracts and optional typed decode helpers.

### Support

- [ALNAttachmentAdapter](api/ALNAttachmentAdapter.md): Attachment adapter protocol for save/read/delete/list operations on binary blobs + metadata.
- [ALNAuth](api/ALNAuth.md): Authentication and authorization helpers for bearer token extraction, JWT verification, and scope/role checks.
- [ALNCacheAdapter](api/ALNCacheAdapter.md): Cache adapter protocol for set/get/remove/clear operations with optional TTL semantics.
- [ALNFileJobAdapter](api/ALNFileJobAdapter.md): Filesystem-backed job queue adapter for durable local/edge deployments.
- [ALNFileMailAdapter](api/ALNFileMailAdapter.md): Filesystem-backed mail adapter that writes deliveries to disk for auditing/testing.
- [ALNFileSystemAttachmentAdapter](api/ALNFileSystemAttachmentAdapter.md): Filesystem-backed attachment adapter for durable binary storage.
- [ALNInMemoryAttachmentAdapter](api/ALNInMemoryAttachmentAdapter.md): In-memory adapter implementation useful for development and tests.
- [ALNInMemoryCacheAdapter](api/ALNInMemoryCacheAdapter.md): In-memory adapter implementation useful for development and tests.
- [ALNInMemoryJobAdapter](api/ALNInMemoryJobAdapter.md): In-memory adapter implementation useful for development and tests.
- [ALNInMemoryLocalizationAdapter](api/ALNInMemoryLocalizationAdapter.md): In-memory adapter implementation useful for development and tests.
- [ALNInMemoryMailAdapter](api/ALNInMemoryMailAdapter.md): In-memory adapter implementation useful for development and tests.
- [ALNJobAdapter](api/ALNJobAdapter.md): Job adapter protocol for enqueue/dequeue/ack/retry operations and queue state diagnostics.
- [ALNJobEnvelope](api/ALNJobEnvelope.md): Immutable leased-job envelope containing identity, payload, attempt counters, and schedule metadata.
- [ALNJobWorker](api/ALNJobWorker.md): Worker orchestration helper that leases due jobs and executes them through a runtime callback.
- [ALNJobWorkerRunSummary](api/ALNJobWorkerRunSummary.md): Summary payload for one worker run, including lease/ack/retry/error counters.
- [ALNJobWorkerRuntime](api/ALNJobWorkerRuntime.md): Worker runtime callback protocol that decides ack/retry/discard disposition for leased jobs.
- [ALNLocalizationAdapter](api/ALNLocalizationAdapter.md): Localization adapter protocol for translation registration, lookup, and locale discovery.
- [ALNLogger](api/ALNLogger.md): Structured logger with configurable output format and level-specific convenience methods.
- [ALNMailAdapter](api/ALNMailAdapter.md): Mail adapter protocol for outbound delivery and delivery snapshot diagnostics.
- [ALNMailMessage](api/ALNMailMessage.md): Mail payload model containing sender/recipients/content/headers/metadata fields.
- [ALNMetricsRegistry](api/ALNMetricsRegistry.md): In-memory metrics registry for counters, gauges, timings, snapshots, and Prometheus text output.
- [ALNPerfTrace](api/ALNPerfTrace.md): Per-request performance stage recorder used for internal timing diagnostics and perf event export.
- [ALNRealtimeHub](api/ALNRealtimeHub.md): In-process pub/sub hub used for websocket channel fanout and simple realtime event routing.
- [ALNRealtimeSubscriber](api/ALNRealtimeSubscriber.md): Realtime callback protocol implemented by websocket/session subscribers.
- [ALNRealtimeSubscription](api/ALNRealtimeSubscription.md): Subscription token returned by realtime hub subscribe calls and used for unsubscribe operations.
- [ALNRedisCacheAdapter](api/ALNRedisCacheAdapter.md): Redis-backed cache adapter implementation compatible with `ALNCacheAdapter` semantics.
- [ALNRetryingAttachmentAdapter](api/ALNRetryingAttachmentAdapter.md): Retry-wrapper adapter implementation with deterministic retry semantics.
- [ALNRetryingMailAdapter](api/ALNRetryingMailAdapter.md): Retry-wrapper adapter implementation with deterministic retry semantics.

## Public Header List

- `src/Arlen/Core/ALNAppRunner.h`
- `src/Arlen/Core/ALNApplication.h`
- `src/Arlen/Core/ALNConfig.h`
- `src/Arlen/Core/ALNOpenAPI.h`
- `src/Arlen/Core/ALNSchemaContract.h`
- `src/Arlen/Core/ALNValueTransformers.h`
- `src/Arlen/Data/ALNAdapterConformance.h`
- `src/Arlen/Data/ALNDatabaseAdapter.h`
- `src/Arlen/Data/ALNDatabaseRouter.h`
- `src/Arlen/Data/ALNDisplayGroup.h`
- `src/Arlen/Data/ALNGDL2Adapter.h`
- `src/Arlen/Data/ALNMigrationRunner.h`
- `src/Arlen/Data/ALNPg.h`
- `src/Arlen/Data/ALNPostgresSQLBuilder.h`
- `src/Arlen/Data/ALNSQLBuilder.h`
- `src/Arlen/Data/ALNSchemaCodegen.h`
- `src/Arlen/HTTP/ALNHTTPServer.h`
- `src/Arlen/HTTP/ALNRequest.h`
- `src/Arlen/HTTP/ALNResponse.h`
- `src/Arlen/MVC/Controller/ALNContext.h`
- `src/Arlen/MVC/Controller/ALNController.h`
- `src/Arlen/MVC/Controller/ALNPageState.h`
- `src/Arlen/MVC/Middleware/ALNCSRFMiddleware.h`
- `src/Arlen/MVC/Middleware/ALNRateLimitMiddleware.h`
- `src/Arlen/MVC/Middleware/ALNResponseEnvelopeMiddleware.h`
- `src/Arlen/MVC/Middleware/ALNSecurityHeadersMiddleware.h`
- `src/Arlen/MVC/Middleware/ALNSessionMiddleware.h`
- `src/Arlen/MVC/Routing/ALNRoute.h`
- `src/Arlen/MVC/Routing/ALNRouter.h`
- `src/Arlen/MVC/Template/ALNEOCRuntime.h`
- `src/Arlen/MVC/Template/ALNEOCTranspiler.h`
- `src/Arlen/MVC/View/ALNView.h`
- `src/Arlen/Support/ALNAuth.h`
- `src/Arlen/Support/ALNLogger.h`
- `src/Arlen/Support/ALNMetrics.h`
- `src/Arlen/Support/ALNPerf.h`
- `src/Arlen/Support/ALNRealtime.h`
- `src/Arlen/Support/ALNServices.h`
