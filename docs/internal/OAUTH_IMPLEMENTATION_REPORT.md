# OAuth / Entra implementation report

Implementation date: 2026-09-11. Identify the reviewable commit with:

```bash
git log -1 --format=%H -- docs/internal/OAUTH_IMPLEMENTATION_REPORT.md
```

## Completed

- `ALNOAuthResourceServer`: provider-neutral RFC 9068 profile, Entra v1/v2 preset,
  strict RSA access-token verification, stable principal, explicit application
  permission policy, and per-request suspension/data-policy hook.
- Reused `ALNOIDCClient`'s RSA/JWK cryptography and `ALNAuth` claims/scope/role
  facilities. Extended `ALNHTTPCompat` with bounded Foundation metadata GETs;
  no parallel crypto stack, password handling or token issuer.
- Bounded discovery/JWKS cache, serialized cooldown/rotation, trusted configured
  issuer/hosts, rejected redirects and untrusted token URL hints, fail-closed
  expiry/outage behavior. No credential/content logging was added.
- Optional MCP integration: canonical resource metadata, path-prefix discovery,
  HTTP 401/403 challenges, fresh backing-route authentication, shared REST/tool
  authorization and startup coverage checks. Legacy modes remain supported;
  configured OAuth endpoints cannot fall back to legacy credentials.
- Placeholder Entra configuration and runnable protected MCP example; runbook,
  public/API documentation, generated API reference, CI coverage and adoption
  handoff. Existing CI required check names and branch protection are unchanged.

## Actual validation evidence

All executed with the repository's clang-based `/usr/GNUstep` environment and
vendored tools-xctest runner, via make targets:

| Check | Result |
| --- | --- |
| `make test-unit` | 706 test methods across 98 test classes passed before the final three additional OAuth regression methods |
| Final `make oauth-check` | 14 OAuth test methods passed; protected example compiled; real loopback HTTP discovery/challenge and valid-legacy-token rejection passed |
| Final `make mcp-check` | 16 existing MCP methods passed; real loopback protocol/JWT/Origin checks passed |
| `make docs-api docs-html ci-docs` | Generated references, HTML build and documentation quality gate passed |
| `git diff --check` | Passed |

OAuth fixtures generate ephemeral RSA keys in memory. Coverage includes invalid
signatures/algorithms/claims, wrong issuer/tenant/audience/version, Graph and
cross-service audiences, expired/future/missing time claims, ID-token rejection,
application-policy/role separation, unknown-key cooldown, rotation, outages,
expired cache, concurrent refresh, metadata/key restrictions, proxy spoofing,
path-prefix discovery, suspension and shared REST/MCP record denial. Foundation
URLProtocol fixtures exercise response bounds, rejection of redirects/non-200s
and timeout. Those are simulated transport cases; the example probes exercise
real local HTTP. No company access/refresh token was used. Full integration,
macOS/Windows runtime and live TLS/Entra acceptance were not executed.

Local read-only CLI evidence: Codex 0.154.0 advertises `--oauth-client-id`;
Claude Code 2.1.261 advertises `--client-id` and `--callback-port`.
No existing client registrations or credential stores were changed.

## Interoperability findings and limits

A read-only fetch of Entra's public `common` v2 metadata showed **no
`code_challenge_methods_supported`**. MCP 2025-11-25 requires that field even for
OIDC discovery. This is a concrete discovery-contract gap, despite Entra's
supported PKCE flow. Preregistration does not solve it. The company tenant's
metadata and actual client behavior remain untested. The runbook proposes an
issuer-preserving metadata remedy first, conditional on supported client
configuration; a maintained federated broker requires a separate decision.
No adapter, broker or authorization server was built.

RS256 is the initial algorithm allowlist; only exact single-string audiences
are accepted. The generic profile needs an explicit issuer permission-type
claim mapping. JWT checks have zero clock skew. Cold refresh is synchronous and
may take two 5-second fetch deadlines. Offline JWT verification does not provide
immediate Entra revocation or Continuous Access Evaluation; applications must
supply suspension policy. Tool catalog filtering is not implemented; execution
is always authorized. API/interactive client registrations must be separate.

No approved tenant configuration was supplied. Live Claude Team Desktop,
Cowork, Claude Code and Codex acceptance is **pending**, not inferred from tests.
No deployment, live research changes, tenant mutations or public route exposure
were performed. The unrelated modified `vendor/gnustep-cli-new` submodule and
untracked `.codex` entry were preserved and excluded from the commit.

## Handoff

- API agent: follow [the migration sequence](STATE_COMPULSORY_POOLING_OAUTH_MIGRATION.md)
  to adopt the commit, keep all six tool contracts, implement record policy and
  suspension, and test an isolated Entra-only instance. Downstream source was
  unavailable here; upstream success does not assert downstream closure.
- DevOps agent: follow [the administrator runbook](../OAUTH_RESOURCE_SERVER.md)
  and migration handoff for single-tenant API/client registrations, exact
  redirects, assignments/consent, PKCE metadata resolution and live renewal
  acceptance. Prepare both gateway paths; deployment requires separate approval.
- Keep the private port-3122 HS256 pilot separate until acceptance. Retire it
  through an explicit revocation/cutover plan; never enable a public fallback.
