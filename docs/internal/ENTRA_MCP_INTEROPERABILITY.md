# Entra/MCP interoperability decision and downstream acceptance

Status: framework operational mitigation and synthetic coverage implemented;
**downstream seamless sign-in remains blocked**. No approved company tenant,
client registrations, assigned test users or HTTPS synthetic endpoint have been
supplied. There is no recommended *proven working* Entra path for all clients
yet. Claiming otherwise would exceed the evidence.

The downstream resource proposal is `https://mcp.invitoep.com/research/mcp`.
This is not an Arlen deployment or framework-owned hostname. Reusable examples
and framework docs use placeholders. No port-3122 or public routing change is
included. The original 14 OAuth tests, 16 MCP tests and both HTTP checks were
also reported passed by independent downstream review; that accepts isolated
integration, not live authentication.

## Evidence and decision

| Candidate | Evidence | Decision |
| --- | --- | --- |
| A: direct Entra with preregistration | All three clients document preregistration. Public common v2 OIDC metadata lacks PKCE capability advertisement; actual company metadata unavailable. | First downstream test candidate after administrator provisioning. Not accepted as an all-client working path. |
| B: metadata-only adapter | Claude Code documents a trusted metadata URL override. No corresponding issuer-preserving override was established for hosted Claude/Cowork or Codex from reviewed documentation. | Do not implement or recommend as a universal fix. Require proof for each client first. |
| C: maintained Entra-federated broker | Keycloak documents OIDC federation, S256 policies, audience mappers and configurable access-token header type. It is a candidate with an explicit contract below, not a tested deployment. | Contingency if A/B cannot meet documented contracts. Separate production identity-service decision required. |

The [MCP 2025-11-25 specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
requires the PKCE capability field even in OIDC metadata. The inspected
[public Entra document](https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration)
omits it. This is a **specification/metadata incompatibility**, not an observed
failure from the company's actual clients. No browser sign-in, token exchange,
renewal or reauthentication failure was observed because those tests cannot
start without approved configuration. Do not interpret absence of an observed
failure as compatibility. Never configure `common` as the resource-server issuer.

[Hosted Claude documentation](https://claude.com/docs/connectors/building/authentication)
states S256 is sent on authorization requests and describes preregistered
credentials; it also documents bounded endpoint response waits. That describes
supported behavior, not evidence that this tenant/endpoint completed a flow.
[Claude Code documentation](https://code.claude.com/docs/en/mcp) identifies a
localhost callback regression in 2.1.229 restored in 2.1.231; installed 2.1.261
is later. Its metadata override can change scope selection, so an override
needs qualified-scope validation as well as issuer preservation.
[Codex documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
requires registering the printed callback, which can have a service-specific
suffix depending on issuer metadata. Do not invent an exact suffix from CLI
help output. Installed versions were checked without changing credentials:
Codex 0.154.0 and Claude Code 2.1.261. Hosted client versions were not available.

## Reproducible checks and their limits

```bash
source tools/source_gnustep_env.sh
make oauth-check mcp-check
python3 tools/oauth/check_discovery.py --self-test
# Administrator supplies a saved approved single-tenant metadata document:
python3 tools/oauth/check_discovery.py --metadata /path/to/tenant-metadata.json \
  --expected-issuer 'https://login.microsoftonline.com/<TENANT_GUID>/v2.0'
```

The offline audit checks only issuer equality, advertised S256, HTTPS endpoints
and authorization-code response type. Eight synthetic cases include missing or
malformed PKCE advertisement, replaced issuer and insecure endpoints. It has
no HTTP proxy, token endpoint, credentials or authorization server. A passing
file cannot prove actual client behavior. The XCTest/HTTP harness independently
covers validation, permissions, routing, outage and rotation using synthetic
keys; no fixture token is a live acceptance result.

## Actual client acceptance matrix

`BLOCKED` means not executed; it is not `FAILED`. Every cell below remains a
separate downstream acceptance gate.

| Required observation | Claude Team Desktop/Cowork | Claude Code | Codex CLI |
| --- | --- | --- | --- |
| Exact version / registration | BLOCKED: hosted version and Web registration unavailable | 2.1.261 observed; BLOCKED: public registration missing | 0.154.0 observed; BLOCKED: public registration missing |
| Tenant metadata and supported discovery | BLOCKED: tenant GUID and approved synthetic HTTPS endpoint missing | BLOCKED: same | BLOCKED: same |
| Browser MFA, code + S256 and redirect matching | BLOCKED: approved user/registration unavailable | BLOCKED: same | BLOCKED: same; exact callback not yet emitted for approved service |
| Qualified scope, resource parameter and actual API audience | BLOCKED: no token issued through approved client flow | BLOCKED: same | BLOCKED: same |
| Initialize, tools/list, authorized tools/call | BLOCKED: no authenticated session | BLOCKED: same | BLOCKED: same |
| Wrong tenant/audience, missing permission and pilot-credential denial | BLOCKED: live client scenario not executed; framework fixtures pass | BLOCKED: same | BLOCKED: same |
| Automatic renewal after natural token expiry | BLOCKED: no approved session/refresh grant | BLOCKED: same | BLOCKED: same |
| Reauthentication after refresh access revocation | BLOCKED: administrator action/session missing | BLOCKED: same | BLOCKED: same |
| Local suspension and Entra revocation delay | BLOCKED: actual-client scenario not run; framework policy/expiry fixtures pass | BLOCKED: same | BLOCKED: same |

Evidence returned later must contain status, version, callback URI without query,
request IDs and match booleans only. No passwords, codes, tokens or research
content. Never substitute edited expiry claims or manually copied tokens for a
client renewal test.

## Contingency C: isolated Keycloak proof-of-concept plan

This is a prepared test design, **not an executed Entra-federated PoC or approval
to deploy a new identity service**. An approved tenant federation registration
is needed before it can test the actual company identity flow. Use a supported,
pinned Keycloak release chosen by DevOps; do not deploy the old release mentioned
below merely because it introduced a feature.

Keycloak documents OIDC identity brokering and audience configuration in its
[administration guide](https://www.keycloak.org/docs/latest/server_admin/).
Its [26.2 release notes](https://www.keycloak.org/2025/04/keycloak-2620-released)
document the `at+jwt` access-token header option, which matters for Arlen's
RFC 9068 profile. Its [OIDC guide](https://www.keycloak.org/securing-apps/oidc-layers)
describes enforcing S256 through client policy.

Proposed deployment/ownership: an isolated test realm and synthetic resource,
owned by DevOps/identity administrators. Production would add a TLS identity
origin, durable database/backups, key rotation, upgrades, monitoring, protected
administration, incident response, session/refresh policy and another availability
dependency. Entra continues company sign-in and MFA; disable broker local-user
password login, self-registration and password grants for this realm. Do not
auto-link users by email. Restrict upstream federation to the one confirmed
Entra tenant and approved identities/assignments.

PoC acceptance contract:

1. Register a separate Entra confidential federation client using the exact
   callback displayed by Keycloak's configured OIDC provider. Configure that
   secret only in approved storage. Use the actual tenant discovery endpoints.
   The three MCP clients register with the broker, not with Entra for this path.
2. Preregister hosted Claude (Web/confidential) and both CLIs (public) at the
   broker, with the client-specific redirects from the runbook. Enable standard
   authorization code/S256; disable implicit, service-account, password and
   exchange grants for these user-only clients.
3. Give each service its own API audience and permission. For research, proposed
   broker `aud` is exactly the canonical research resource URI as a **single
   string**. Remove default/unrelated audience mappers rather than relaxing
   Arlen. Advertise only that service's scopes and discovery authority. Verify
   behavior with the clients' `resource` parameter; do not assume it.
4. Use signed RS256 `at+jwt` access tokens with issuer, sub, exp, iat, client_id,
   scope and an explicit permission-type claim. Configure locked per-client
   mappers for `client_id` and `idtyp=user` only on these code-only clients;
   no application grant can share that mapping. Map approved permissions into
   the token; do not grant them just because authentication succeeded.
5. Arlen uses `profile=rfc9068`, the real broker issuer/discovery/JWKS host,
   exact research audience and `allowApplicationPermissions=false`. Keep
   `permissionTypeClaim=idtyp`, `delegatedPermissionValue=user`. Its principal
   is issuer + broker sub; the application must explicitly migrate/map this to
   existing records, not assume it equals Entra tid:oid. Preserve suspension and
   client allowlists. Do not add Entra and broker audiences to one permissive mode.
6. Clients receive broker-issued research tokens; Entra federation tokens stay
   inside the broker. No Entra/Graph token is passed to research, and no research
   token is passed to another resource. Test ID-token and cross-resource denial.
7. Run every actual-client matrix row, including natural refresh, refresh
   revocation, upstream assignment removal, and local suspension. Broker sessions
   can outlive Entra changes: define/enforce that revocation delay and never claim
   instantaneous upstream revocation from offline Arlen validation.

A metadata-only adapter would avoid those token/session responsibilities, but
only if all clients can discover it while retaining the **real** issuer and
endpoints. No generic discovery contract may be silently rewritten to impersonate
Entra. Do not disable PKCE or rely on undocumented client tolerance.

## Next administrator action

Use [the provisioning request](ENTRA_TEST_ADMIN_HANDOFF.md). Confirm tenant and
authority first; return the exact non-secret configuration and assignments.
Arrange synthetic-only HTTPS reachability for hosted-client acceptance while
research-data routes remain disabled. Until then, framework work can complete,
but selecting a proven all-client live path cannot.
