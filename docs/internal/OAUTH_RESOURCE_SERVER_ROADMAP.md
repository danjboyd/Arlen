# OAuth resource-server delivery roadmap

## Implemented in this change

- Reuse existing OIDC RSA/JWK cryptography, Foundation HTTP compatibility and
  route authorization contracts; expose a provider-neutral resource server.
- Entra v1/v2 preset with strict configured issuer/tenant/audience binding,
  distinct delegated/app-only policy, stable principal and suspension hook.
- Bounded HTTPS metadata, JWKS expiry/rotation/cooldown, fail-closed validation.
- MCP canonical resource metadata and 401/403 challenges for path-prefixed
  services, with consistent fresh authorization of backing REST requests.
- Placeholder Entra example, administrator runbook, downstream migration handoff
  and focused security fixtures integrated into the existing Linux quality gate.

## Pending external acceptance / separate decisions

- Approved tenant resources and client registrations; exact client redirect,
  consent, scope, audience, refresh and reauthentication evidence.
- Resolve the observed omission of PKCE capability from Entra public metadata.
  Evaluate a supported issuer-preserving metadata remedy first; propose a
  maintained broker separately if clients cannot support it. No issuer or broker
  implementation is authorized by this roadmap.
- Downstream adoption, six-tool record-policy regressions, approved gateway
  rollout, private-pilot coexistence and eventual HS256 retirement.

See [implementation evidence](OAUTH_IMPLEMENTATION_REPORT.md),
[administrator runbook](../OAUTH_RESOURCE_SERVER.md) and
[API/DevOps handoff](STATE_COMPULSORY_POOLING_OAUTH_MIGRATION.md).
