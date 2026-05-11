# Arlen Status

This is a capability-level snapshot of what Arlen ships today, what is in
preview, and what is in flight. For engineering history, see
`docs/internal/STATUS_HISTORY.md` and `docs/internal/PHASE*_ROADMAP.md`.

## Platform Support

| Platform | Toolchain | Status |
|---|---|---|
| Linux | clang-built GNUstep | Production baseline. Authoritative target. |
| macOS | Apple Objective-C runtime | Verified. Recommended for development on macOS. |
| Windows | CLANG64 | Preview. Packaged-release contract, not the primary production target. |

## Capability Maturity

### Shipped

| Area | Capability |
|---|---|
| HTTP | HTML and JSON routing, controllers, middleware, route metadata |
| Templates | EOC (`.html.eoc`) transpiler, layouts, partials, forms, live fragments |
| Auth | Sessions, CSRF, rate limiting, password reset, TOTP MFA, recovery codes, passkeys/WebAuthn, OIDC/provider login |
| Auth UI | `headless`, `module-ui`, and `generated-app-ui` ownership modes |
| Modules | `auth`, `admin-ui`, `jobs`, `notifications`, `storage`, `ops`, `search` |
| Data layer | PostgreSQL-first migrations, schema codegen, typed SQL helpers, `ALNSQLBuilder` |
| ORM (optional) | ArlenORM SQL layer over PostgreSQL |
| Realtime | WebSocket, SSE, live fragments, durable event streams (append/replay/auth) |
| API tooling | OpenAPI generation, interactive explorer, JSON-first scaffolds |
| Runtime | `boomhauer` dev server, `propane` production manager |
| Deploy | `arlen deploy` orchestration, named targets, release inventories, SSH transport |
| Frontend | Generated TypeScript validators/query contracts/module metadata, optional React helpers |
| Diagnostics | `arlen doctor`, `deploy doctor`, fault injection, release certification |
| Search | Authoritative PostgreSQL, Meilisearch, and OpenSearch engines with policy-scoped semantics |

### Preview

| Area | Notes |
|---|---|
| Windows CLANG64 | `main`-branch bootstrap and packaged-release preview. See `WINDOWS_CLANG64.md`. |
| MSSQL data layer | Backend-neutral seam with native common-scalar and binary transport on supported builds. PostgreSQL remains the authoritative path. |
| Dataverse | Web API client, OData helpers, and typed codegen ship; runtime-inactive by default. See `DATAVERSE.md`. |
| Twilio Verify SMS MFA | Disabled-by-default secondary factor. TOTP-first remains the core MFA contract. |

### In Flight

| Area | Direction |
|---|---|
| Multi-worker state safety | Process-local state contracts and doctor/deploy warnings shipped; durable-store examples, worker identity diagnostics, and confidence coverage in progress. |
| Production-runtime reliability | Investigating a tracked descriptor-growth bug under sustained load (operator diagnostics and regression gates). |

## Reading Order for Evaluators

1. [First App Guide](FIRST_APP_GUIDE.md)
2. [Getting Started](GETTING_STARTED.md)
3. [Modules](MODULES.md)
4. [Deployment Guide](DEPLOYMENT.md)
5. [API Reference](API_REFERENCE.md)

For engineering history, milestone detail, and dated handoffs, see
`docs/internal/`.
