# Phase 35 Roadmap

Status: delivered
Last updated: 2026-04-17

## Goal

Build a route and middleware policy layer that can express named access
policies, with proxy-aware source IP allowlisting as the first concrete policy
type and `/admin` as the first framework consumer.

Phase 35 should avoid baking IP allowlists directly into routes or the admin
module. The durable abstraction is:

- routes and path prefixes can resolve named policies
- policies can compose multiple access-control checks
- source IP allowlisting is one policy capability, not the whole feature
- proxy-derived client IPs are trusted only when the direct peer is a trusted
  proxy

The first production shape should support configuration like:

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

And route-side attachment like:

```objc
[router get:@"/admin"
 controller:@"AdminController"
    action:@"index"
  policies:@[ @"admin" ]];
```

Follow-up subphases add plist-backed route definitions as another registration
surface for the same router. They must not create a second route system:
plist loading validates declarative route records and calls the existing
`ALNApplication`/`ALNRouter` registration APIs so route matching, route
metadata, policy evaluation, reverse lookup, logging, and diagnostics stay on
one authoritative route table.

## Security Boundary

IP allowlisting is an outer gate only. Protected administrative surfaces should
still layer:

1. source IP allowlist
2. real admin authentication
3. CSRF protection
4. audit logging
5. revision history / rollback where the feature mutates operational state

Forwarded headers are never trusted by default. `Forwarded` and
`X-Forwarded-For` may influence the resolved client IP only when the immediate
socket peer matches `security.trustedProxies`.

Default behavior:

- if no trusted proxy is configured, use the direct socket peer IP
- if trusted proxies are configured and the direct peer is trusted, resolve the
  original client from `Forwarded` or `X-Forwarded-For`
- if the direct peer is not trusted, ignore forwarded headers
- if source IP cannot be resolved for a protected route, deny

## 35A. Policy Model and Configuration Contract

Status: delivered 2026-04-17

Goal:

- define the configuration schema for route policies and trusted proxies
- keep policy names deterministic and app-author friendly
- preserve a clear distinction between route selection and policy evaluation

Deliverables:

- `security.routePolicies.<name>` config parsing
- `security.trustedProxies` config parsing
- policy fields for:
  - `pathPrefixes`
  - `requireAuth`
  - `trustForwardedClientIP`
  - `sourceIPAllowlist`
- deterministic diagnostics for malformed policy names, invalid CIDRs, and
  unsupported policy fields

Acceptance target:

- app config can declare named policies without changing route code
- invalid policy config fails deterministically with actionable diagnostics

## 35B. CIDR and Client IP Resolution Runtime

Status: delivered 2026-04-17

Goal:

- implement reusable IPv4/IPv6 CIDR matching
- implement trusted-proxy-aware client IP resolution
- avoid trusting spoofable forwarded headers from public clients

Deliverables:

- IPv4 CIDR parser and matcher
- IPv6 CIDR parser and matcher
- direct socket peer IP extraction surface
- `Forwarded` parser for `for=`
- `X-Forwarded-For` parser that handles multi-hop lists deterministically
- trusted proxy check against the immediate peer
- fail-closed behavior when protected routes cannot resolve a client IP

Acceptance target:

- source IP decisions are deterministic for direct, trusted-proxy, untrusted
  proxy, malformed-header, and unresolved-client cases

## 35C. Route Attachment and Path-Prefix Matching

Status: delivered 2026-04-17

Goal:

- let policies apply by config path prefix and by explicit route metadata
- make composition deterministic when multiple policies match

Deliverables:

- route-side `policies:` attachment API
- path-prefix policy matcher
- policy merge/evaluation order
- diagnostics for unknown route policy names

Acceptance target:

- `/admin` can be protected entirely by config
- individual routes can opt into named policies explicitly
- when multiple policies apply, the result is deterministic and fail-closed

## 35D. Policy Middleware Evaluation

Status: delivered 2026-04-17

Goal:

- evaluate route policies at the middleware boundary before protected handlers
  run
- preserve clear status codes and machine-readable diagnostics

Deliverables:

- route policy middleware
- source IP allowlist enforcement
- auth-required policy hook that can delegate to current/future auth modules
- response behavior for policy denial
- structured logging fields that distinguish:
  - denied source IP
  - unresolved client IP
  - failed authentication
  - later policy stages

Acceptance target:

- policy denial prevents controller/action execution
- logs distinguish source-IP denial from auth failure

Delivered notes:

- `ALNRoutePolicyMiddleware` validates `security.trustedProxies` and
  `security.routePolicies` during application startup.
- `sourceIPAllowlist` supports IPv4 and IPv6 CIDR ranges. Bare IP addresses are
  treated as exact-host matches.
- `trustForwardedClientIP` is policy-specific and only trusts `Forwarded` or
  `X-Forwarded-For` when the immediate peer matches `security.trustedProxies`.
- Path-prefix policies are evaluated by sorted policy name, then route-side
  policies are appended in route registration order with duplicates removed.
- Route-side policy references fail startup when the named policy is not
  configured.
- Denied requests return `403`, set `X-Arlen-Policy-Denial-Reason`, commit the
  response before controller dispatch, and log `route_policy.denied` with the
  policy, reason, route, path, client IP, and client-IP source fields.

## 35E. `/admin` First Consumer

Status: delivered 2026-04-17

Goal:

- make `/admin` the first framework-owned consumer of named route policies
- keep IP allowlisting as an outer gate, not the sole admin protection model

Deliverables:

- default `admin` policy wiring for `/admin`
- documentation for configuring local-only and LAN/admin-subnet access
- compatibility behavior when no admin policy is configured
- clear guidance that auth and CSRF remain required for real admin surfaces

Acceptance target:

- admin routes can be protected by `security.routePolicies.admin`
- existing apps without admin policy config retain documented behavior

## 35F. Spoofing and Proxy Regression Suite

Status: delivered 2026-04-17

Goal:

- lock down the security-critical edge cases around forwarded headers and CIDR
  matching

Deliverables:

- tests for IPv4 CIDR allow/deny
- tests for IPv6 CIDR allow/deny
- tests for direct peer IP allow/deny
- tests for trusted proxy resolving `Forwarded`
- tests for trusted proxy resolving `X-Forwarded-For`
- tests for spoofed `X-Forwarded-For` from an untrusted direct peer
- tests for malformed forwarded headers and unresolved client IP
- integration coverage that proves denied protected routes do not execute the
  target action

Acceptance target:

- spoofed forwarded-header attempts are denied or ignored deterministically

## 35G. Audit, Diagnostics, and Operator Docs

Status: delivered 2026-04-17

Goal:

- make policy behavior inspectable enough for operators and coding agents to
  diagnose safely

Deliverables:

- policy decision log schema
- docs for `security.trustedProxies`
- docs for `security.routePolicies`
- `/admin` policy examples
- troubleshooting guidance for reverse-proxy deployments
- warnings that IP allowlists do not replace auth/CSRF/audit controls

Acceptance target:

- operators can configure admin source IP allowlisting behind nginx without
  trusting public spoofed headers

## 35H. Confidence Lane and Closeout

Status: delivered 2026-04-17

Goal:

- add a focused confidence lane that proves the route policy layer remains
  working as security-sensitive behavior evolves

Deliverables:

- `phase35` focused test target or confidence script
- CI/docs alignment if a new lane is added
- roadmap/status closeout notes

Acceptance target:

- Phase 35 has a repeatable local verification command and documented CI
  expectation before being marked delivered

Closeout notes:

- `modules/admin-ui` now copies `security` config into its mounted child app
  and attaches the configured `admin` policy to all admin routes when
  `security.routePolicies.admin` exists.
- Existing apps with no `admin` route policy keep the prior admin behavior.
- `MiddlewareTests` covers IPv4/IPv6 CIDR decisions, trusted `Forwarded`,
  trusted `X-Forwarded-For`, untrusted forwarded-header spoofing, malformed
  forwarded clients, unresolved direct peers, and controller non-execution on
  policy denial.
- `Phase16FTests` covers admin UI policy attachment and source IP denial before
  admin auth handling.
- `docs/ROUTE_POLICIES.md` documents the operator contract, reverse-proxy
  troubleshooting, denial reasons, and the warning that IP allowlists do not
  replace auth, CSRF, audit logging, or rollback controls.
- `make phase35-confidence` writes focused artifacts to
  `build/release_confidence/phase35/`.

## 35I. Plist Route Schema and Validation

Status: delivered 2026-04-17

Goal:

- define a deterministic plist schema for static route registration
- make the schema author-friendly without expanding routing semantics beyond
  the existing Objective-C route API
- reject malformed route records before the app starts serving traffic

Non-goal:

- do not introduce a second route matcher or a parallel route metadata model

Proposed shape:

```plist
routes = (
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

Deliverables:

- documented `routes` array schema
- required fields for `method`, `path`, `controller`, and `action`
- route-name validation, with names strongly encouraged and required anywhere
  policy, reverse-route, or diagnostics behavior needs stable identity
- optional `formats`, `guardAction`, and `policies` fields that map directly to
  existing router metadata
- startup diagnostics for unknown keys, unsupported methods, invalid paths,
  invalid controller/action strings, duplicate names, and malformed policy
  arrays

Acceptance target:

- invalid plist route definitions fail deterministically with actionable
  diagnostics and no partial route table mutation

Delivered notes:

- Added top-level `routes` config validation for static route records.
- Required fields are `method`, `path`, `controller`, and `action`.
- Optional `name`, `formats`, `guardAction`, and `policies` map directly to
  existing route metadata.
- Startup rejects unknown keys, unsupported methods, invalid paths, unresolved
  controller classes, invalid action/guard names, duplicate configured names,
  malformed string arrays, and unknown plist-referenced policy names.
- Invalid configured routes fail with `invalid_configured_routes` and do not
  register any configured route.

## 35J. Plist Loader Into Existing Router APIs

Status: delivered 2026-04-17

Goal:

- implement plist route loading as a thin adapter over existing route
  registration APIs
- preserve one authoritative `ALNRoute`/`ALNRouter` model

Deliverables:

- app configuration hook that loads declarative routes at startup
- route registration through `ALNApplication`/`ALNRouter` methods rather than
  direct mutation of router internals
- controller-class resolution and action validation consistent with
  code-defined routes
- deterministic ordering between code-defined and plist-defined routes
- rollback behavior when any configured route is invalid

Acceptance target:

- a plist route produces the same `ALNRoute` object shape, matching behavior,
  route name, formats, guard action, controller/action dispatch, and policy
  metadata as the equivalent Objective-C route registration call

Delivered notes:

- `ALNApplication` loads configured routes during `startWithError:` after app,
  module, and code-defined route registration.
- The loader validates the full array first, then calls
  `registerRouteMethod:path:name:formats:controllerClass:guardAction:action:policies:`.
- Configured routes therefore share the existing `ALNRoute` objects,
  `ALNRouter` route table, matching behavior, route compile path, and dispatch
  behavior with code-defined routes.
- Duplicate-name validation checks names already present in the router before
  configured routes are registered.

## 35K. Policy and Admin Integration for Plist Routes

Status: delivered 2026-04-17

Goal:

- make plist-defined routes first-class consumers of the Phase 35 policy layer
- keep `/admin` policy wiring compatible with code-defined and declarative
  routes

Deliverables:

- `policies` field support in plist route records
- validation that plist-referenced policy names exist under
  `security.routePolicies`
- tests covering path-prefix policies on plist-defined routes
- tests covering explicit plist route policy attachment
- documentation showing `/admin` and non-admin examples

Acceptance target:

- route policies behave identically whether the route was registered from
  Objective-C code or from plist configuration

Delivered notes:

- Plist route records support `policies = (...)`.
- Policy names referenced by plist routes must exist under
  `security.routePolicies` before any configured route is registered.
- `ApplicationTests` covers explicit policy attachment on a plist-defined
  route, source IP denial, and allowed dispatch through the same route policy
  middleware used by code-defined routes.
- `docs/CONFIGURATION_REFERENCE.md` documents the route schema, validation
  behavior, startup failure contract, and the one-router design constraint.

## 35L. Route Inspection and Documentation

Status: delivered 2026-04-17

Goal:

- make declarative routes inspectable and easy to compare with code-defined
  routes
- document when plist routes are appropriate and when Objective-C route code is
  the better tool

Deliverables:

- route inspection output that includes whether a route was configured from
  plist or code, without changing runtime semantics
- app-author docs for static route plist registration
- configuration reference updates
- troubleshooting notes for duplicate names, missing controllers/actions,
  unsupported methods, and unknown policy names
- examples that combine `routes` with `security.routePolicies`

Acceptance target:

- an operator or coding agent can inspect the effective route table and see the
  same policy/name/controller/action data regardless of registration source

Delivered notes:

- `ALNRoute` now carries source metadata. Code-defined routes default to
  `code`; top-level plist `routes` records are marked `plist` after
  registration through the existing application/router APIs.
- `[app routeTable]` exposes `source` alongside existing method, path, name,
  controller, action, format, guard, policy, auth, schema, and OpenAPI fields.
- `boomhauer --print-routes` and `arlen routes` include `[code]` or `[plist]`
  in the printed route table.
- `docs/CONFIGURATION_REFERENCE.md`, `docs/CLI_REFERENCE.md`, and
  `docs/GETTING_STARTED.md` document static plist routes, policy examples,
  route inspection, and common startup diagnostics.

## 35M. Confidence Lane and Closeout for Plist Routes

Status: delivered 2026-04-17

Goal:

- add focused regression coverage proving plist route registration stays a
  wrapper around the existing route system

Deliverables:

- tests proving parity between plist-defined and code-defined routes
- tests proving startup fails without partial mutation for invalid route plist
  records
- tests proving duplicate route names and unknown policies are rejected
- confidence-lane update that includes plist route coverage
- roadmap/status closeout notes when delivered

Acceptance target:

- Phase 35 plist route support can be verified with one focused local command,
  and that command proves there is still only one authoritative route table

Delivered notes:

- `ApplicationTests` cover plist/code route-table parity, no-partial-mutation
  startup failures, duplicate route names, unknown policy names, and policy
  enforcement on plist-defined routes.
- `RouterTests` cover route-table `source = code` for normal route
  registration.
- `make phase35-confidence` now includes `ApplicationTests` and records plist
  route coverage in the Phase 35 manifest.
- Phase 35 is closed with both the route/middleware policy layer and the plist
  route registration follow-up delivered.
