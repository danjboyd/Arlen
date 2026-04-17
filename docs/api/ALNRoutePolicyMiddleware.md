# ALNRoutePolicyMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNRoutePolicyMiddleware.h`

Middleware that evaluates named route policies before protected route handlers
run.

Route policies are configured under `security.routePolicies`. The middleware
supports path-prefix matching, route-side policy names, IPv4/IPv6 CIDR source
IP allowlists, trusted-proxy-aware `Forwarded` and `X-Forwarded-For` client IP
resolution, and `requireAuth` checks.

Denied requests return `403`, set `X-Arlen-Policy-Denial-Reason`, and log
`route_policy.denied` with policy, reason, route, path, client IP, and client-IP
source fields.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `validateSecurityConfiguration:` | `+ (nullable NSError *)validateSecurityConfiguration:(NSDictionary *)config;` | Validate route-policy and trusted-proxy configuration. | Called during application startup; returns deterministic diagnostics for invalid policy names, invalid CIDRs, unsupported fields, and malformed policy values. |
