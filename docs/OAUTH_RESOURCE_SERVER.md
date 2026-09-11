# OAuth resource servers and Entra administration

Arlen's opt-in `ALNOAuthResourceServer` validates API access tokens and establishes
`context.stash[ALNOAuthPrincipalStashKey]`. The optional MCP module installs it
when `mcp.oauth` is configured. Existing session and HS256 deployments retain
their behavior; OAuth-protected paths require the original OAuth bearer token
on every dispatch. There is no credential fallback.

Start with [the protected MCP example](../examples/mcp_app/README.md) and its
[placeholder configuration](../examples/mcp_app/entra.example.json).
This feature provides resource-server validation and discovery. **Direct Entra
sign-in has a known metadata compatibility gap:** the public v2 discovery
document inspected omits the PKCE capability field required by MCP. See the
interoperability decision below before planning rollout. Live client
sign-in acceptance against your Entra tenant is a separate administrator gate.
No tenant resources or public routes are created by this example.

## Framework contract

Use `mcp.oauth` for configuration-only installations. For an application policy,
construct `ALNOAuthResourceServer` with `initWithConfiguration:documentLoader:authorizationPolicy:error:`
and assign it to `mcp.resourceServer` before registering the MCP plugin. Pass
`nil` for the document loader in production. Configuration freezes at
installation. For REST-only applications, register the resource server directly
as an `ALNPlugin`, before application authorization middleware.

```objc
ALNOAuthResourceServer *resource = [[ALNOAuthResourceServer alloc]
    initWithConfiguration:oauthConfiguration
    documentLoader:nil
    authorizationPolicy:^BOOL(NSDictionary *principal, ALNContext *context) {
      // Implement with your application service and durable local policy store.
      return [accessPolicy permitsSubject:principal[@"subject"]
                                 clientID:principal[@"clientID"]
                                  request:context.request];
    } error:&error];
if (!resource) return NO;
mcp.resourceServer = resource;
return [application registerPlugin:mcp error:&error];
```

The policy is an application hook, not a supplied `accessPolicy` implementation.
It runs after cryptographic verification, before controller execution, on both
the outer MCP request and a fresh dispatch of the backing REST route. Read path
parameters from the request/context and perform database-backed record checks
in the policy or controller. Do not assume validated schema values exist yet
for every middleware stage. A policy returning NO stops dispatch with 403.
A thrown policy exception fails the request; policy code must not put secrets
or record content into exception messages.

Route `requiredScopes`, `requiredRoles`, guards, and existing policy middleware
continue to apply. `ALNAuth` scope/role helpers work with the verified identity.
Tools backed by routes use those same routes, original credentials, and the full
application dispatcher. Custom tools declare equivalent scope/role/policy
metadata. `tools/list` currently shows the registered catalog; visibility is not
an authorization decision. `tools/call` always enforces access. OAuth 401/403
from an inner dispatch becomes an HTTP challenge on the outer MCP request.

`protectedPaths` defaults to `["/"]`. Prefix matching respects segment
boundaries. Narrow it only to an explicit collection containing every MCP and
REST entry point to the service. MCP startup rejects uncovered backing routes.
Use separate application/resource-server instances and API audiences for
separate services. Do not install competing identity middleware after OAuth or
reuse one configuration across unrelated resources. Health/static responses
handled before the application dispatcher are not authorization-protected data
routes; do not place sensitive data there.

### Principal

| Field | Contract |
| --- | --- |
| `subject` | Entra: `tenantID:objectID`; generic profile: verified `sub` |
| `issuer`, `tokenSubject` | Verified issuer and original subject |
| `tenantID`, `objectID` | Entra `tid` and `oid`; empty for the generic profile |
| `clientID` | Entra v2 `azp`, v1 `appid`, generic `client_id` |
| `permissionType` | `delegated` or `application` |
| `scopes`, `roles` | Verified permissions; application tokens expose no delegated scopes |
| `expiresAt`, `resource` | Expiry timestamp and configured canonical resource |

Generic identities must be keyed by **issuer and subject together**. Email,
UPN, display names, and caller-provided identity headers are not authorization
keys. The principal omits raw tokens and profile PII. For suspension, use a
shared durable store keyed by subject and/or client, consulted by the policy
on each request; define explicit fail-closed behavior if that store fails.

### Verification and operations

Only RS256 is supported; `algorithms` must equal `["RS256"]`. JWTs are bounded
to 32 KiB; critical JOSE extensions are rejected. The selected key must be an
unambiguous RSA signing key (2048–8192-bit encoded modulus bound). Issuer,
single string audience, expiry, issued-at, and optional not-before are checked
without clock skew; synchronize backend clocks. Entra additionally requires
not-before, matching tenant/version, object identity and client identity.
ID-token profiles cannot substitute for access tokens.

`profile: "rfc9068"` is the provider-neutral default and requires `at+jwt` or
`application/at+jwt`. Since RFC 9068 does not identify the grant type, configure
`permissionTypeClaim`, `delegatedPermissionValue`, and `applicationPermissionValue`
(defaults: `idtyp`, `user`, `app`) to a trusted issuer's explicit claim contract.
Unknown permission types fail closed. Entra has its own preset/profile: delegated
tokens need nonempty `scp`; app-only tokens need `idtyp=app` and roles.
Application access requires both `allowApplicationPermissions: true` and an
explicit policy; the policy must allow the service principal/client and roles.
Delegated scopes never authorize application-only access.

Trusted `discoveryURL` must return the exact configured `issuer`. Its HTTPS
`jwks_uri` host must be in `jwksAllowedHosts` (default: discovery host). Token
`jku`/`x5u` never choose a network destination. If a JWK declares an issuer, it
must match; Entra's `{tenantid}` key-issuer template is resolved only with the
configured tenant. Redirects, non-200 responses and documents exceeding 256 KiB
are rejected; each Foundation fetch has a 5-second deadline. JWKS has at most
64 keys. Query-bearing discovery/JWKS URLs and custom Entra signing-key query
extensions are currently unsupported.

Cache age defaults to 300 seconds (30–3600). Refresh cooldown defaults to
30 seconds (5–cache age). Expiry or an unknown key triggers at most one refresh
per cooldown per instance, serialized across threads; a refresh attempts at
most two requests. Bad signatures for known keys never trigger refresh. Fresh
trusted cached keys remain usable during an outage; expired keys do not.
There is no stale-on-error extension, persistent cache, or unbounded per-key
negative cache. New keys can be temporarily rejected during cooldown. By default fetches are synchronous; allow for up to two fetch deadlines on a
cold request. For serialized runtimes use the maintenance mode below.

Arlen does not fetch refresh tokens, implement password handling, or issue
OAuth credentials. Offline signature validation **does not immediately observe
Entra logout, user disablement, consent removal, or refresh-token revocation**.
Existing access tokens may survive until expiry. Use the local suspension hook
for immediate service-level denial. Continuous Access Evaluation/claims
challenge handling is not implemented.

## Entra administrator setup

1. Create a single-tenant **API registration** for research, separate from every
   interactive client registration. Set `api.requestedAccessTokenVersion` to 2
   for the recommended configuration. Expose a delegated scope such as
   `api://<RESEARCH_API_APPLICATION_GUID>/<DELEGATED_SCOPE>` and choose its consent
   policy. The route checks the short `scp` value `<DELEGATED_SCOPE>`.
2. Set the backend tenant GUID and exact issuer; do not use `common`,
   `organizations`, or caller-supplied tenants. Use the v2 API application GUID
   as audience. For a deliberate v1 deployment, configure its actual API
   Application ID URI/audience and v1 discovery/issuer; do not accept both
   versions/audiences automatically. The API's token version controls validation
   metadata even when the client uses the v2 authorization endpoint.
   [Microsoft token validation](https://learn.microsoft.com/en-us/entra/identity-platform/access-tokens)
3. Create separate client registrations for hosted Claude, Claude Code, and
   Codex. Add the research delegated permission to each, grant administrator
   consent where required, and preauthorize approved clients if desired. API
   consent does not replace application record-access policy. Use a test group
   and assignment requirements on enterprise applications, and verify unassigned
   users are denied. Enforce company MFA/Conditional Access in Entra.
4. If user roles are useful, define API app roles with user membership and assign
   the intended group/users. If daemon access is later approved, define separate
   application roles, assign only approved service principals, request the
   `idtyp` optional access-token claim, and enable Arlen's explicit app policy.
   Key local records by tenant/object identity and check the client actor.
   [Microsoft claim guidance](https://learn.microsoft.com/en-us/entra/identity-platform/claims-validation)
5. Configure each client below, then complete the acceptance checklist. Client
   secrets belong only in the hosted client's supported protected credential
   storage; never in Arlen resource-server configuration. Native CLI clients
   should use public-client authorization code + S256 PKCE without a secret.

Entra v2 selects the API through fully qualified scopes. Advertise the research
scope and `offline_access` in `scopesSupported`, so the client requests renewable
credentials. Do not add Graph scopes or use a Graph access token for research.
The canonical MCP resource remains `https://<PUBLIC_MCP_HOST>/research/mcp`; it
need not equal Entra's GUID `aud`. Arlen binds that configured resource to its
one exact audience. Verify this mapping during live acceptance.
[Entra scopes](https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc)

### Client-specific registration and redirects

Documentation reviewed and local CLI help checked on 2026-09-11. These are setup
instructions, not a live acceptance claim. Framework fixtures require no tenant or deployment. Actual client acceptance
is an application-owned gate; no approved downstream test tenant information
was supplied during implementation. All direct sign-in entries remain subject
to the PKCE metadata gap described below.

| Client | Registration / exact callback configuration | Acceptance status |
| --- | --- | --- |
| Claude Team: Desktop / Cowork via remote custom connector | Separate confidential Web client; register `https://claude.ai/api/mcp/auth_callback`. Enter client ID and secret in connector advanced settings. A Team owner/admin enables the connector, then each user authenticates. | Documented route; live Entra/Cowork untested |
| Claude Code | Separate public Mobile/Desktop client; register `http://localhost:8765/callback`; use the same fixed port below. | Local 2.1.261 flags verified; live Entra untested |
| Codex CLI | Separate public Mobile/Desktop client; register the **exact URL printed by `codex mcp add`**, including its server-specific suffix when present. Fix callback listener port to 8766 as below. | Local 0.154.0 preregistration flag verified; live Entra untested |

Hosted Claude's connector runs through Anthropic infrastructure, requiring a
publicly reachable endpoint. Local Desktop stdio configuration is a separate
mechanism and does not provide Cowork access. Hosted surfaces support token
renewal; validate refresh and subsequent reauthentication with your tenant's
policies. [Claude connector authentication](https://claude.com/docs/connectors/building/authentication),
[Team connector setup](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)

```bash
claude mcp add --transport http --client-id '<CLAUDE_CODE_CLIENT_GUID>' \
  --callback-port 8765 research https://<PUBLIC_MCP_HOST>/research/mcp
# Within Claude Code, open /mcp and authenticate.

codex -c mcp_oauth_callback_port=8766 mcp add research \
  --url https://<PUBLIC_MCP_HOST>/research/mcp \
  --oauth-client-id '<CODEX_CLIENT_GUID>'
# Register the callback printed above, then persist the port and log in:
codex mcp login research
```

Persist Codex `mcp_oauth_callback_port = 8766` at the top of its config, or
`callback_port = 8766` in `[mcp_servers.research.oauth]`. For a callback URL with
an explicit port, match the configured listener port. Do not blindly register
`/callback`: Codex can append a callback ID derived from the full service URL
when the authorization server does not advertise issuer-bound responses.
Its current docs make the displayed callback authoritative. Changing the public
service path can require new redirect registration. Server-advertised scopes
are preferred during login. [Codex OAuth configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

Claude Code supports preregistered public clients and automatic refresh. Its
optional `oauth.authServerMetadataUrl` can point to the exact tenant's v2 OIDC
metadata if discovery fails, but inspect the scopes used: this override can
change scope selection. Do not paper over an audience mismatch.
[Claude Code MCP configuration](https://code.claude.com/docs/en/mcp)

For Codex's HTTP `127.0.0.1` callback, Entra's portal may require application
manifest/API registration instead of its redirect text box. Configure a public
client redirect, preserve the exact path, and verify the listener's actual port
matching. Do not use SPA redirect classification or wildcards as a workaround.
[Microsoft redirect restrictions](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url)

### Direct Entra interoperability decision

Observed primary-document evidence: the public Entra
[`common` v2 discovery document](https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration)
on 2026-09-11 contains no `code_challenge_methods_supported`, no registration
endpoint, no CIMD support declaration, and no `none` token-auth method. Its
scope list contains OIDC defaults, not the application API scope. This public
metadata inspection is **not** a request against an approved company tenant.
Never configure the resource server to trust `common`.

MCP 2025-11-25 requires clients to refuse authorization when OIDC metadata lacks
`code_challenge_methods_supported`, despite Entra's separately documented PKCE
implementation. Thus direct Entra + strict MCP discovery is not established by
preregistration, and can fail before browser sign-in. Inspect the approved
single-tenant document and record whether the same omission exists. Client
versions may differ in enforcement; do not rely on a client bypass of this
requirement as proof of standards compliance.

Smallest proposed remedy, **not implemented here**: first seek corrected Entra
metadata or a supported client discovery override with a reviewed metadata-only
adapter. Such an adapter would explicitly assert Entra's supported S256 PKCE,
keep the real tenant issuer and original Entra authorize/token/JWKS endpoints,
and retain preregistered clients. It must not receive tokens, mint credentials,
or pretend a gateway URL is the Entra issuer. Claude Code documents a metadata
URL override; no equivalent cross-client hosted-Cowork/Codex route was verified
in this work. A metadata overlay is therefore a candidate for targeted
validation, not a claimed universal solution. Do not publish one until its
issuer/discovery contract has passed the exact clients' acceptance checks.
If clients cannot preserve the issuer using supported configuration, propose a
maintained Entra-federated OAuth broker separately, with its own resource-bound
tokens and lifecycle. Do not write an Arlen authorization server to work around
an untested client path.

Preregistration addresses the lack of automatic client registration without an
Arlen authorization server. The remaining acceptance gate is the *whole flow*:
client discovery of Entra OIDC metadata, S256 PKCE, callback matching, scope
selection, token audience, and refresh. MCP clients send `resource` even when
the authorization server does not support that parameter. Entra's documented
v2 flow chooses resources with `scope`; the reviewed sources do not establish
that every target client/tenant combination interoperates. Resource-parameter handling is an additional unverified boundary beyond the
observed PKCE metadata gap. Neither establishes a need to build a bespoke broker.
[MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)

If a live client requests only OIDC defaults instead of the qualified research
scope, first fix advertised scope/client configuration and reauthenticate. If
it cannot use preregistration, upgrade the client. If an exact Entra response
shows an unsupported discovery, `resource`, client-authentication, or redirect
contract that configuration cannot resolve, record the non-secret error code,
client version and failing protocol step. Propose a maintained OAuth gateway
with Entra federation only then; scope its token audience and key lifecycle
separately. A token-issuing broker is a new security boundary and requires a
separate design approval. Do not build an ad hoc exchange or relay a token for
one service into another.

### Renewal and live acceptance

Clients own authorization-code exchange, secure token storage and refresh.
`offline_access` is needed for Entra refresh tokens. When refresh fails due to
expiry/revocation/Conditional Access, the client must return to interactive
sign-in. Backend 401 responses include discovery information; they do not
silently mint replacement credentials.
[Entra authorization-code and refresh flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow)

For **each** target client, record version, test tenant, configured callback,
and pass/fail (no tokens, codes, or secret-bearing callback query strings):

1. Fresh credential store: discover the path-prefixed resource, sign in through
   Entra MFA, consent, initialize MCP, list tools, and call an allowed tool.
2. Verify locally that the received API token has the configured version,
   tenant and audience, with research permission. Record only match booleans.
3. Reach normal access-token expiry and verify client refresh without copying
   credentials; restart the client and verify secure persistence.
4. Remove/revoke refresh access in the approved test environment and verify
   interactive reauthentication. Separately suspend the local subject and
   confirm immediate 403 on both MCP and REST despite a still-valid JWT.
5. Test an unassigned user, missing scope/role, another service's token, and a
   direct backend request. Confirm no controller/tool execution on denial.
6. Verify all six application tools with representative record allow/deny cases.

## Gateway and operations

The proposed routes below are a handoff, not a deployment performed by Arlen:

| Public path | Backend behavior |
| --- | --- |
| `/research/mcp` | Route to the research service preserving method, path, Authorization, Accept, Content-Type, MCP-Protocol-Version and response status/challenges |
| `/.well-known/oauth-protected-resource/research/mcp` | Unauthenticated GET to that same service; preserve the full metadata path |
| Future service MCP and corresponding well-known paths | Route to their own resource servers/audiences |

Configure public `resourceURL` exactly. Arlen builds metadata/challenges from
configuration only, never Host/Forwarded/X-Forwarded-* values. The gateway
terminates trusted TLS and strips incoming forwarded identity headers. Avoid
login-page redirects, response wrapping, caching authorized responses, or
rewriting 401/403. No gateway token exchange is needed. Entra authorization,
token and discovery endpoints remain on Entra; do not fabricate gateway
`/.well-known/oauth-authorization-server` metadata. No ambiguous root protected
resource document is needed when several services share the host.

Arlen preserves its existing stateless Streamable HTTP profile: POST JSON
responses, protocol version 2025-11-25, no session IDs, GET/DELETE 405, and no
persistent SSE stream. Keep reverse-proxy response buffering/timeouts consistent
with this contract and preserve `WWW-Authenticate`. Set allowed origins only
for clients that actually send an approved Origin. Metadata is publicly readable.

For private remote backends, use a protected internal link or TLS as appropriate;
loopback forwarding is valid only when the gateway and backend share a host.
Backend authentication remains mandatory even if network filtering is bypassed.
Keep backend ports private and avoid putting bearer tokens in URLs.

Operational troubleshooting:

- 401: check clock, API audience/version, exact issuer/tenant, key-cache expiry,
  outbound DNS/TLS, and permitted JWKS host. Cold discovery failures fail closed.
- 403: check short scope names, user roles/assignments, client allowlist, local
  suspension, and record policy. App-only access needs a separate explicit policy.
- `AADSTS50011`: compare actual callback scheme/host/port/path against the client
  registration, especially Codex's callback suffix and public-client platform.
- Repeated consent/refresh failures: check qualified scopes, `offline_access`,
  client registration type and tenant Conditional Access; clear the client's
  stored authorization and repeat the approved flow.
- Log only status, request ID, route, timing, and sanitized operational error
  categories. This implementation emits no tokens or metadata content in logs.
  Disable proxy/debug body capture and Authorization/Cookie logging. Application
  hooks and trace exporters must follow the same rule.

Run `source tools/source_gnustep_env.sh` then `make oauth-check mcp-check` for
controlled local regressions. These checks do not establish live Entra acceptance.

## Serialized-runtime maintenance and readiness

All settings are application configuration. Arlen requires no hostname, Entra
tenant, public listener, proxy, or identity-service deployment of its own.
Use placeholders in reusable configuration; bind an actual service resource only
in the downstream application. Live provider/client acceptance belongs to that
application, independently of framework fixture coverage.

For a serialized runtime, the recommended configuration is:

```json
{
  "refreshOnRequest": false,
  "preflightOnStart": true,
  "jwksMaxAgeSeconds": 300,
  "refreshCooldownSeconds": 30
}
```

These keys belong inside the existing OAuth resource-server configuration.
`preflightOnStart` defaults to false and `refreshOnRequest` defaults to true for
compatibility. Preflight performs bounded discovery/JWKS retrieval before the
application starts; failure prevents startup. It is not a sign-in compatibility
test. After startup, schedule `refreshSigningKeysWithError:` every 30 seconds
on **one dedicated application maintenance worker**, not the HTTP event loop or
its timers. Use the existing application's scheduler if it already has one.
The worker must call the same in-process resource-server instance: an external
process cannot warm its memory cache. Stop/join that worker during application
shutdown, allowing for the two bounded fetches. No perpetual worker is started
implicitly by the framework.

`isReady` is a nonblocking, no-network check for an unexpired trusted
metadata/JWKS snapshot. Wire it into an application-owned **private** readiness
endpoint or supervisor callback and return 503 when false. The stock `/readyz`
does not automatically include this new check; do not claim it does. Choose a
readiness route outside `protectedPaths`, protect it through the application's
private observability/network policy, and avoid exposing keys, tenant details,
or token content. This snapshot check cannot prove a key for every incoming
`kid`, token correctness, or user authorization.

In maintenance mode, requests never wait for network retrieval. A missing or
unknown key gets 401 immediately; only the maintenance worker fetches. During
rotation a new key may remain unavailable until the next successful maintenance
cycle. During an outage, existing keys work only until the original cache
expiry; afterwards readiness is false and protected requests fail closed. There
is no extension of expired trust. The application decides how its gateway treats
an unready backend; preserve authentication challenges if requests reach it.

Refreshes are single-flight behind a separate fetch lock, with a short cache
publication monitor. Existing-key validation and readiness checks do not wait
on discovery I/O. A maintenance caller can wait behind another maintenance
caller; keep exactly one scheduled worker rather than queueing work per request.
The production loader remains bounded to two 5-second request timeouts, subject
to scheduler/poll granularity. Warmup moves that cost to startup; it cannot
remove issuer/network outages or the rotation visibility interval.

Synthetic reproduction (no provider credentials, external hostname, or public
routing required):

```bash
source tools/source_gnustep_env.sh
make oauth-check mcp-check
```

`OAuthResourceServerTests` measures a synchronous cold fetch using two controlled
150-ms loader delays, then holds a maintenance refresh in flight while checking
existing-key validation, unknown/expired-key rejection, readiness and rotation
recovery. The test logs timings only, never tokens. `check_discovery.py --self-test`
checks synthetic PKCE/issuer/discovery cases; it is not an actual client test.
For a downstream administrator's saved metadata document, audit without network:

```bash
python3 tools/oauth/check_discovery.py --metadata /path/to/metadata.json \
  --expected-issuer 'https://<ISSUER_HOST>/<TENANT>/v2.0'
```

An audit pass establishes only the listed metadata properties. It does not
establish preregistration, token authentication method, redirect support,
resource/scope semantics, refresh, or any client's acceptance.
