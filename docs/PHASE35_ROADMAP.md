# Phase 35 Roadmap

Status: in progress; 35A-35D delivered, 35E-35H planned
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
