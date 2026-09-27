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
- `serveStatic`: serve files from `public/`
- `staticAllowExtensions`: extensions Arlen may serve from `public/`
- `mimeTypes`: optional extension -> `Content-Type` overrides for static mounts
  and controller file responses (see [Static files](STATIC_FILES.md#content-types))
- `listenBacklog`: socket listen backlog
- `connectionTimeoutSeconds`: request/connection timeout baseline
- `enableReusePort`: opt-in socket reuse for supported deployments

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
- `session.secure`
- `session.sameSite`

CSRF config:

- `csrf.enabled`
- `csrf.headerName`
- `csrf.queryParamName`

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
CSP later as the frontend becomes more specific.

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
  `OPTIONS`, or `ANY`
- `path`: absolute route path beginning with `/`
- `controller`: Objective-C controller class name
- `action`: action name without a trailing colon

Optional route fields:

- `name`: stable route name; strongly recommended for diagnostics and reverse
  routing
- `formats`: accepted route formats
- `guardAction`: guard action name without a trailing colon
- `policies`: named route policies from `security.routePolicies`

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
  docsUIEnabled = YES;
  docsUIStyle = "interactive";
  title = "Arlen API";
  version = "0.1.0";
  description = "Generated by Arlen";
};
```

Useful keys:

- `openapi.enabled`
- `openapi.docsUIEnabled`
- `openapi.docsUIStyle`
- `openapi.title`
- `openapi.version`
- `openapi.description`

Use route metadata plus these app-level keys to shape your generated API docs.

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

Multipart `requestLimits` keys are `maxMultipartParts` (128), `maxMultipartFieldBytes` (65536), `maxMultipartFileBytes` (1048576), and `maxMultipartHeaderBytes` (16384). All values must be positive whole numbers. Bare or quoted decimal plist values are normalized to numbers; invalid values fail configuration loading with an error naming the key. See [Multipart Uploads](MULTIPART_UPLOADS.md) for buffering behavior and a 110 MiB request configuration.

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
