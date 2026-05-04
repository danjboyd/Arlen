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
- `poolSize`: adapter connection pool size

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
