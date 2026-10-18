# Configuration Reference

This guide covers the configuration keys and inspection flows that ordinary
Arlen app authors touch first.

Arlen loads configuration from:

- `config/app.plist`
- `config/environments/<environment>.plist`

Use this command to inspect the merged effective config for one environment:

```bash
/path/to/Arlen/bin/arlen config --env development --json
```

Secret values print as `[redacted]`; add `--show-secrets` to see them. See
[CLI Reference](CLI_REFERENCE.md#arlen-config---env-name---json---show-secrets).

## 1. Minimal Mental Model

Start with `config/app.plist` for defaults that apply everywhere. Override only
the environment-specific values in `config/environments/development.plist`,
`test.plist`, or `production.plist`.

The scaffolded `config/app.plist` is the best source of truth for the keys most
apps need first.

## 2. Common Server Keys

- `host`: bind address for `boomhauer`
- `port`: default app port
- `logFormat`: `text` or `json`
- `performanceLogging` (default: on, off in `production`): record per-stage
  request timing in the access log. `ARLEN_PERFORMANCE_LOGGING` overrides it.
- `performanceHeaders` (default: on, off in `production`): while
  `performanceLogging` is on, also send the timing as `X-Arlen-Total-Ms`,
  `X-Arlen-Parse-Ms`, `X-Arlen-Response-Write-Ms` and `X-Mojo-Total-Ms`
  response headers. They let any client time requests, so keep them off on
  public deployments. `ARLEN_PERFORMANCE_HEADERS` overrides it.
- Detailed exception pages (reason, stack, file paths) are shown only when the
  environment is `development` or `test`. Every other environment, including
  `staging`, gets the production error response.
- `serveStatic`: serve files from `public/`, mounted under `/static/` — the
  scaffold's own `public/health.txt` answers at `/static/health.txt`, not at
  `/health.txt`
- `staticAllowExtensions`: extensions Arlen may serve from `public/`
- `staticCacheControl`: optional `Cache-Control` for the default `/static` mount,
  either one string or a glob dictionary (`ARLEN_STATIC_CACHE_CONTROL` supplies
  a single string); `staticMounts` entries take the same form as `cacheControl`
  (see [Static files](STATIC_FILES.md#cache-control))
- `spaFallback`: optional single-page-app shell for unmatched HTML navigations
  (`file`, `excludePrefixes`, `prefix`, `cacheControl`, `allowDottedPaths`; see
  [Static files](STATIC_FILES.md#spa-history-fallback))
- `mimeTypes`: optional extension -> `Content-Type` overrides for static mounts
  and controller file responses (see [Static files](STATIC_FILES.md#content-types))
- `listenBacklog`: socket listen backlog
- `connectionTimeoutSeconds`: request/connection timeout baseline. It also
  limits how long an idle keep-alive connection stays open between requests.
- `enableReusePort`: opt-in socket reuse for supported deployments
- `runtimeLimits`: HTTP server concurrency limits
  - `maxConcurrentHTTPWorkers` (default `8`): threads that run requests.
  - `maxConcurrentHTTPSessions` (default `256`): open HTTP connections,
    including idle keep-alive connections. Further connections get a `503`.
  - `maxQueuedHTTPConnections` (default `256`): connections waiting for a
    worker.
  - `keepAliveParkAfterMilliseconds` (default `5`, `0` parks at once): after a
    keep-alive response, a worker waits this long for the next request on the
    same connection. If none starts, the connection is handed to a watcher
    thread and the worker moves on, so idle browser connections don't hold
    workers. The watcher hands the connection back to a worker when the next
    request arrives, and closes it after `connectionTimeoutSeconds`. Pipelined
    requests are served without parking. When other connections are waiting
    for a worker, a keep-alive connection is parked after every response,
    even a busy one, so connections take turns instead of holding workers. The
    serialized `requestDispatchMode` keeps each connection on one worker. On
    Windows the watcher uses `WSAPoll`.
  - `webSocketPingIntervalSeconds` (default `25`, `0` disables): after this long
    without a frame from the client, the server pings an open WebSocket; a
    client that sends nothing for another interval is closed with `1001`. A
    receive-only subscriber that answers pings stays connected however long it
    is idle. Environment override: `ARLEN_WEBSOCKET_PING_INTERVAL_SECONDS`.
  - Server-sent event streams and WebSocket sessions hold a worker for as long
    as they stay open. Size `maxConcurrentHTTPWorkers` above the number of
    streams you expect to be open at once, plus headroom for ordinary
    requests.

Generated apps start with:

```plist
{
  host = "127.0.0.1";
  port = 3000;
  logFormat = "text";
  serveStatic = YES;
}
```

## 3. Request Limits

`requestLimits` controls parser/body ceilings:

- `maxRequestLineBytes`
- `maxHeaderBytes`
- `maxBodyBytes`

Raise these only for real application needs. The defaults are intentionally
bounded.

Instead of raising `maxBodyBytes` for the whole app, give only the routes that
need it a larger limit, either `route.maxBodyBytes` in code or `maxBodyBytes` on
a plist route. The server finds the route from the request line and applies its
limit to `Content-Length` as soon as the head is parsed: a larger body gets `413`
before any of it is read. Routes without an override keep `requestLimits.maxBodyBytes`,
which can also be lower than the default. No middleware or controller runs
before this check or before the body is read; route matching is the only input.
On a route with an override, multipart parsing uses that limit for the whole body
and allows one file part to use all of it. Bodies above `spoolThresholdBytes`
stream to disk (see [Multipart Uploads](MULTIPART_UPLOADS.md)).

Chunked request bodies (`Transfer-Encoding: chunked`) are accepted by the
default `llhttp` parser. They are buffered in memory, never spooled, and their
decoded size is held to `requestLimits.maxBodyBytes`; a per-route override
can't be checked before the body arrives, because there is no
`Content-Length`. Only the request head (request line and headers) counts
toward `maxHeaderBytes`, not the chunk-size lines. The legacy parser
(`ARLEN_HTTP_PARSER_BACKEND=legacy`) rejects chunked bodies with `400`.

Other request-head rules:

- `Expect: 100-continue` gets an interim `100 Continue` once the head has
  passed the size checks, before the client sends the body. A request rejected
  at that point (for example `413`) gets the final status instead. Any other
  expectation gets `417`.
- An HTTP/1.1 request must carry exactly one `Host` header; a duplicate or a
  missing one gets `400` (RFC 9112 §3.2). HTTP/1.0 requests may omit it.
- An absolute-form target (`GET http://example.com/path HTTP/1.1`) is routed by
  its path, and its authority replaces the `Host` header.
- Responses written before the application runs (`400`, `408`, `413`, `417`,
  `431`) carry the configured `securityHeaders`.

## 4. Database

The scaffold includes:

```plist
database = {
  connectionString = "";
  adapter = "postgresql";
  poolSize = 8;
};
```

Common keys:

- `connectionString`: DSN or connection string
- `adapter`: `postgresql` by default; optional MSSQL support is also available
- `poolSize`: adapter connection pool size (env `ARLEN_DB_POOL_SIZE`)
- `poolAcquireTimeoutSeconds`: seconds a request waits for a free pooled
  connection when all `poolSize` connections are in use; `0` (default) fails
  immediately with a pool-exhausted error (env
  `ARLEN_DB_POOL_ACQUIRE_TIMEOUT_SECONDS`). Arlen normalizes this key; apps
  that create their own `ALNPg`/`ALNMSSQL` pass it to the adapter's
  `acquireTimeout`. See
  [ArlenData](ARLEN_DATA.md#connection-pool-acquire-timeout).

If you are just starting, set the connection string first and leave the rest
alone until you need different pool behavior.

## 4.1 Durable State Intent

Production apps with more than one `propane` worker should declare how
request-spanning app-owned state is made durable:

```plist
state = {
  durable = YES;
  mode = "database";
  target = "default";
};
```

Common keys:

- `durable`: `YES` when mutable app-owned state lives outside worker memory
- `mode`: `database`, `sqlite`, `file`, or another documented durable strategy
- `target`: the database/storage target name, usually `default`

Environment overrides:

- `ARLEN_STATE_DURABLE`
- `ARLEN_STATE_MODE`
- `ARLEN_STATE_TARGET`

This is an operator/developer intent signal. Arlen does not claim it can
statically prove every app-owned store is durable. The signal drives production
doctor/deploy warnings for multi-worker apps.

## 4.1a Storage Module Signing Secret

When the `storage` module is installed, `storageModule.signingSecret` signs
its upload and download tokens. `ARLEN_STORAGE_SIGNING_SECRET` overrides it.
The secret must be at least 32 characters. Outside `development` and `test` the
module refuses to configure without one; see
[Storage Module](STORAGE_MODULE.md#signing-secret).

## 4.2 Dataverse (Optional)

Arlen's Dataverse surface is compiled in but runtime-inactive by default. Apps
only use it when they explicitly configure or instantiate Dataverse helpers.

Common config shape:

```plist
dataverse = {
  serviceRootURL = "https://example.crm.dynamics.com/api/data/v9.2";
  tenantID = "00000000-0000-0000-0000-000000000000";
  clientID = "11111111-1111-1111-1111-111111111111";
  clientSecret = "replace-me";
  pageSize = 500;
  maxRetries = 2;
  timeout = 60;
  targets = {
    sales = {
      serviceRootURL = "https://example.crm.dynamics.com/api/data/v9.2";
    };
  };
};
```

Common keys:

- `dataverse.serviceRootURL` or `dataverse.serviceRoot`
- `dataverse.tenantID` / `tenantId`
- `dataverse.clientID` / `clientId`
- `dataverse.clientSecret`
- `dataverse.pageSize`
- `dataverse.maxRetries`
- `dataverse.timeout`

Named targets can live under either:

- `dataverse.targets.<name>`
- `dataverseTargets.<name>`

The Dataverse runtime helper and CLI/codegen paths also read environment overrides:

- `ARLEN_DATAVERSE_URL` or `ARLEN_DATAVERSE_SERVICE_ROOT`
- `ARLEN_DATAVERSE_TENANT_ID`
- `ARLEN_DATAVERSE_CLIENT_ID`
- `ARLEN_DATAVERSE_CLIENT_SECRET`
- `ARLEN_DATAVERSE_PAGE_SIZE`
- `ARLEN_DATAVERSE_MAX_RETRIES`
- `ARLEN_DATAVERSE_TIMEOUT`

Target-specific overrides append `_<TARGET>` in uppercase, for example
`ARLEN_DATAVERSE_URL_SALES`.

For environment overrides, `ARLEN_DATAVERSE_URL` may be either a bare
environment URL like `https://example.crm.dynamics.com` or the explicit Web API
service root. Arlen normalizes a bare environment URL to
`/api/data/v9.2` automatically.

## 5. Session and CSRF

Session config:

- `session.enabled`
- `session.secret`
- `session.cookieName`
- `session.maxAgeSeconds`
- `session.secure` (default: on in `production`, off elsewhere; generated apps
  leave it unset so this default applies)
- `session.sameSite`

CSRF config:

- `csrf.enabled`
- `csrf.headerName`
- `csrf.queryParamName`
- `csrf.exemptPathPrefixes`: optional array of literal absolute paths (not `/`).
  Unsafe requests to a listed path, or below it, skip the check only when they
  carry no session cookie, which suits bearer-authenticated API clients such as
  MCP in a mixed browser app. Requests with the session cookie still need a
  token. Invalid entries fail startup with error `339`.

The CSRF token is created the first time a request reads it
(`-[ALNContext csrfToken]`, which form helpers and module pages call), and only
then is a session started and a session cookie sent. Requests that never read a
token, including cookieless `GET`/`HEAD` for static-ish routes, get no
`Set-Cookie`, so they cannot replace a signed-in browser's session.

For browser-authenticated apps, enabling sessions usually comes before enabling
CSRF. In stricter environments, Arlen expects a real session secret rather than
an empty placeholder.

A rejected unsafe request returns `403`. Requests that prefer JSON (an `Accept`
of `application/json`, an `/api` path, or `apiOnly`) get the structured error
envelope with the stable code `csrf_invalid`:

```json
{"error":{"code":"csrf_invalid","message":"CSRF token missing or invalid","status":403,"request_id":"...","correlation_id":"..."}}
```

Other clients get the plain-text `csrf verification failed` body. SPA clients
can match on `error.code == "csrf_invalid"` to refresh their token and retry.
Tokens are compared in constant time.

## 6. Rate Limits and Security Headers

Rate limiting:

- `rateLimit.enabled`
- `rateLimit.requests`
- `rateLimit.windowSeconds`

Security headers:

- `securityHeaders.enabled`
- `securityHeaders.contentSecurityPolicy`

Many apps can keep the generated security-header defaults and only tighten the
CSP later as the frontend becomes more specific. The headers cover every response, including static
files, 404s and built-in endpoints, not only routed ones (see
[Response Headers](RESPONSE_HEADERS.md#concurrent-security-headers)).

Operability endpoints:

`/metrics` and `/clusterz` answer anonymous requests by default. `/clusterz`
reports the node ID (hostname) and worker layout, so production apps that are
reachable from untrusted networks should restrict them:

- `observability.operabilityToken` (env `ARLEN_OPERABILITY_TOKEN`): require
  `Authorization: Bearer <token>`. Other requests get `401`.
- `observability.operabilityLoopbackOnly` (env
  `ARLEN_OPERABILITY_LOOPBACK_ONLY`, default `NO`): answer only requests whose
  peer is a loopback address and that carry no `Forwarded`,
  `X-Forwarded-For` or `X-Real-IP` header. Other requests get `403`.

When both are set, a request must pass both. `/healthz`, `/readyz` and
`/livez` are not affected. `arlen doctor --env production` warns when neither
is set.

## 6.1 Route Policies

Route policies are named access-control checks evaluated by middleware before a
protected controller/action runs. The first policy capabilities are path-prefix
matching, route-side attachment, source IP allowlisting, and an auth-required
gate.

Example:

```plist
security = {
  trustedProxies = (
    "127.0.0.1/32",
    "10.0.0.0/8",
    "::1/128"
  );

  routePolicies = {
    admin = {
      pathPrefixes = ("/admin");
      requireAuth = YES;
      trustForwardedClientIP = YES;
      sourceIPAllowlist = (
        "127.0.0.1/32",
        "10.0.0.0/8",
        "203.0.113.10/32"
      );
    };
  };
};
```

Policy names must start with a letter or underscore and may then contain
letters, digits, or underscores. Invalid names, invalid CIDR ranges, unsupported
policy fields, and route-side references to unknown policies fail application
startup with deterministic diagnostics.

Policy keys:

- `pathPrefixes`: URL path prefixes protected by the policy
- `sourceIPAllowlist`: IPv4 or IPv6 CIDR ranges allowed through the outer gate
- `requireAuth`: deny when the request has no authenticated subject
- `trustForwardedClientIP`: allow the policy to use proxy-provided client IP
  headers, but only when the direct peer matches `security.trustedProxies`

Proxy behavior is fail-closed for protected routes. Without trusted proxies,
Arlen uses the direct socket peer IP. With trusted proxies configured, Arlen only
uses `Forwarded` or `X-Forwarded-For` when the immediate peer is trusted; public
clients cannot opt into those headers themselves. If Arlen cannot resolve a
client IP for a protected allowlist check, the request is denied.

Denied route-policy requests return `403`, set
`X-Arlen-Policy-Denial-Reason`, and log `route_policy.denied` with distinct
reasons such as `source_ip_denied`, `direct_peer_unresolved`,
`forwarded_client_unresolved`, and `authentication_required`.

Route-side attachment is also available for routes that should opt into a named
policy independent of path prefix:

```objc
[app registerRouteMethod:@"GET"
                    path:@"/admin"
                    name:@"admin_index"
                 formats:nil
         controllerClass:[AdminController class]
             guardAction:nil
                  action:@"index"
                policies:@[ @"admin" ]];
```

IP allowlisting is an outer gate only. Real administrative surfaces should still
use authentication, CSRF protection for browser flows, audit logging, and
revision history or rollback for operational changes.

The framework admin UI is wired as the first built-in consumer. If
`security.routePolicies.admin` exists, all mounted `/admin` routes attach that
policy. Apps without an `admin` route policy keep the existing admin behavior.
For reverse-proxy deployments, configure `security.trustedProxies` with only the
private proxy peers that connect directly to Arlen.

See [Route Policies](ROUTE_POLICIES.md) for `/admin` examples, denial log
fields, troubleshooting guidance, and the `make phase35-confidence`
verification lane.

## 6.2 Plist Route Definitions

Static routes can be declared in plist configuration with the top-level
`routes` array. This is only a declarative registration surface over the
existing route system: Arlen validates every configured route, then registers
valid entries through the same `ALNApplication`/`ALNRouter` APIs used by
Objective-C route code.

Example:

```plist
routes = (
  {
    method = "GET";
    path = "/admin";
    name = "admin.index";
    controller = "AdminController";
    action = "index";
    policies = ("admin");
  },
  {
    method = "GET";
    path = "/";
    name = "home";
    controller = "HomeController";
    action = "index";
  },
  {
    method = "POST";
    path = "/admin/pages/:id";
    name = "admin.pages.update";
    controller = "AdminPagesController";
    action = "update";
    policies = ("admin");
  }
);
```

Routes can be combined with the same named policy configuration used by
code-defined routes:

```plist
security = {
  routePolicies = {
    admin = {
      pathPrefixes = ("/admin");
      sourceIPAllowlist = ("127.0.0.1/32", "10.0.0.0/8");
    };
  };
};
```

Required route fields:

- `method`: one of `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`,
  `OPTIONS`, or `ANY`. `GET` routes also answer `HEAD` unless a `HEAD` or `ANY`
  route matches first.
- `path`: absolute route path beginning with `/`
- `controller`: Objective-C controller class name
- `action`: action name without a trailing colon

Optional route fields:

- `name`: stable route name; strongly recommended for diagnostics and reverse
  routing
- `formats`: accepted route formats
- `guardAction`: guard action name without a trailing colon
- `policies`: named route policies from `security.routePolicies`
- `maxBodyBytes`: request body limit for this route (positive integer; see
  [Request Limits](#3-request-limits)); invalid values fail with `invalid_max_body_bytes`

Configured routes are loaded during application startup after normal app and
module route registration. Invalid configured routes fail startup with
`invalid_configured_routes`, include per-field diagnostics under `details`, and
do not partially mutate the route table. Duplicate configured route names,
unknown keys, unsupported methods, missing controller classes, invalid paths,
malformed string arrays, and unknown policy names are rejected before any
configured route is registered.

Use plist routes for static, data-shaped route tables. Keep dynamic or
conditional route registration in Objective-C code.

Route inspection uses the same route table for Objective-C and plist routes.
`[app routeTable]` includes the same method, path, name, controller, action,
formats, guard, and policy fields for both sources, plus `source = "code"` or
`source = "plist"`. `arlen routes` / `boomhauer --print-routes` prints that
source in brackets so operators can compare configured and code-defined routes
without inferring provenance from file layout.

Troubleshooting:

- `duplicate_route_name`: route names must be unique across code-defined routes
  and all configured routes.
- `unknown_controller`: the `controller` string must resolve to an Objective-C
  class linked into the app binary.
- `unsupported_method`: `method` must be one of the documented HTTP method
  names above.
- `unknown_route_policy`: each plist route `policies` entry must exist under
  `security.routePolicies`.
- `invalid_action` / `invalid_guard_action`: use the action name without the
  Objective-C trailing colon.

## 7. Auth and API Helpers

Auth:

- `auth.enabled`
- `auth.bearerSecret`
- `auth.issuer`
- `auth.audience`

API helper behavior:

- `apiHelpers.responseEnvelopeEnabled`

If you are building JSON APIs, turn on auth only when you are ready to supply
real secrets and issuer/audience values.

## 8. OpenAPI

Generated apps include:

```plist
openapi = {
  enabled = YES;
  docsUIStyle = "interactive";
  title = "Arlen API";
  version = "0.1.0";
  description = "Generated by Arlen";
};
```

Useful keys:

- `openapi.enabled`
- `openapi.docsUIEnabled` (default: on, off in `production`; generated apps leave
  it unset so `/openapi` is not served in production)
- `openapi.docsUIStyle`
- `openapi.title`
- `openapi.version`
- `openapi.description`

Use route metadata plus these app-level keys to shape your generated API docs.

The docs UI works under the default `securityHeaders.contentSecurityPolicy`
(`default-src 'self'`): its pages load CSS and JS from `/openapi/assets/*`
instead of inline blocks. If you set a stricter policy, keep `'self'` allowed
for `style-src`, `script-src`, and `connect-src` on those routes.

## 9. Compatibility, Plugins, and Propane Accessories

Other scaffolded sections:

- `compatibility.pageStateEnabled`
- `plugins.classes`
- `propaneAccessories.workerCount`
- `propaneAccessories.gracefulShutdownSeconds`
- `propaneAccessories.respawnDelayMs`
- `propaneAccessories.reloadOverlapSeconds`

`plugins.classes` is where `arlen generate plugin` and plugin/manual wiring land.

`propaneAccessories` is the production process-manager config surface.

## 10. Suggested Workflow

For most new apps:

1. Set `host` and `port` only if the defaults are wrong for your machine.
2. Set `database.connectionString` when you are ready for persistence.
3. Enable `session` and `csrf` together for browser stateful flows.
4. Configure `auth` only when you have real secrets and a route/auth plan.
5. Inspect the merged effective config with `arlen config --json` before
   debugging runtime behavior.

## 11. Related Guides

- `docs/FIRST_APP_GUIDE.md`
- `docs/APP_AUTHORING_GUIDE.md`
- `docs/MODULES.md`
- `docs/LITE_MODE_GUIDE.md`

## Optional notifications and search module limits

- `notificationsModule.outbox.maxEntries` (default `1000`) and
  `notificationsModule.inbox.maxEntriesPerRecipient` (default `200`) cap the
  notifications outbox and each inbox; the oldest entries are dropped. See
  [Notifications Module](NOTIFICATIONS_MODULE.md#retention-limits).
- The search module rejects `q` longer than 256 characters (`422`) and clamps
  `autocomplete_limit`/`suggestions_limit` to 25. See
  [Search Module](SEARCH_MODULE.md#query-limits).

## Optional MCP module configuration

`mcp.enabled` defaults to `NO`. Explicit registration is required for every tool.
Settings include `path` (default `/mcp`), `providerClass`, `requiredScopes`,
`requiredRoles`, `policies`, `allowedOrigins` (default empty), `maxOutputBytes`
(default 262144), and `requestsPerMinute` (default 120). Authentication and
existing request policies remain active. See [MCP Module](MCP_MODULE.md).

## OAuth-protected MCP and REST

Use the opt-in OAuth resource server and Entra preset for company API access.
See the [configuration and administrator runbook](OAUTH_RESOURCE_SERVER.md) for a protected
example, client preregistration, public discovery routes, and live acceptance
requirements. `mcp.oauth` requires OAuth bearer credentials without HS256/session
fallback; REST routes and MCP calls reuse Arlen scope, role, and application policies.

For serialized request runtimes, configure `refreshOnRequest: false` and
`preflightOnStart: true`, schedule key maintenance on an application worker, and
wire `isReady` into private readiness. The OAuth runbook documents the tradeoff;
framework tests require no tenant or public deployment.

Multipart `requestLimits` keys are `maxMultipartParts` (128), `maxMultipartFieldBytes` (65536), `maxMultipartFileBytes` (1048576), and `maxMultipartHeaderBytes` (16384). Request bodies and multipart file parts larger than `spoolThresholdBytes` (1048576) are spooled to private temporary files under `spoolDirectory` (an absolute path; default the system temp directory) instead of memory. All values must be positive whole numbers. Bare or quoted decimal plist values are normalized to numbers; invalid values fail configuration loading with an error naming the key. See [Multipart Uploads](MULTIPART_UPLOADS.md) for buffering behavior and a 110 MiB request configuration.

## Auth Module OIDC Providers

Configure `authModule.providers.<identifier>` with `enabled = YES` and
`type = "oidc"`. Provider identifiers contain only ASCII letters, digits,
underscores, or hyphens; `stub` is reserved.

| Key | Contract/default |
| --- | --- |
| `issuer` | Required exact HTTPS issuer; discovery must match it. |
| `discoveryURL` | Required HTTPS discovery URL on an allowed endpoint host. |
| `clientID` | Required web/public client identifier and ID-token audience. |
| `redirectURI` | Required registered HTTPS callback URI. |
| `clientSecretEnvironmentKey` | Required nonempty environment secret for confidential clients; never a literal secret. |
| `tokenEndpointAuthMethod` | `client_secret_post` by default; `none` for public PKCE clients. |
| `scopes` | Defaults to `(openid, profile, email)`; must include `openid`. |
| `subjectClaim` | Verified claim used for the principal; defaults to `sub`. |
| `tenantClaim`, `allowedTenants` | Configure together; nonempty allowlist required. Produces `<tenant>:<subject>`. |
| `endpointAllowedHosts` | Lowercase host allowlist for discovery/authorization/token endpoints; defaults to issuer host. |
| `jwksAllowedHosts` | Lowercase JWKS host allowlist; defaults to endpoint allowlist. |
| `ctaLabel` | Login button text; defaults to `Continue with <identifier>`. |
| `preset` | Optional. `google` fills in `type`, `issuer`, `discoveryURL`, `scopes`, `tokenEndpointAuthMethod`, `ctaLabel`, and endpoint/JWKS allowed hosts derived from the preset's endpoints. Explicit keys win. Unknown or unsupported presets fail startup. |
| `failureRedirect` | Optional local path for failed browser callbacks; overrides `authModule.failureRedirect`. Receives `?error=<code>&provider=<identifier>`. See [Auth Module](AUTH_MODULE.md#failure-redirect). |
| `admission` | Optional sign-in allowlist, checked after ID-token verification and before the resolver: `requireVerifiedEmail`, `allowedEmails`, `allowedEmailsEnvironmentKey`, `allowedDomains`, `requireHostedDomain`, `rejectionMessage`. See [Auth Module](AUTH_MODULE.md#admission-policy). |

`authModule.hooks.providerSessionResolverClass` is required for real providers.
Its class implements `ALNAuthProviderSessionResolver` and decides whether a
verified principal maps to an application user. There is no automatic email
linking or user creation on this path.

`authModule.localPassword.enabled` and `authModule.providers.stub.enabled`
default to false when a real provider is enabled, true otherwise. Explicit
values override those defaults. Older copied manifests may explicitly enable
stub; turn it off in application configuration. The same choices apply to
HTML and API routes. `hooks.oidcTransportClass` is an optional trusted transport
injection, primarily for deterministic tests.

See [Auth Module](AUTH_MODULE.md#configurable-oidc-login-including-microsoft-entra)
for the complete Entra example, callback/session semantics, transport limits,
resolver implementation, and upgrade instructions.
