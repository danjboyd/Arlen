# Research MCP: administrator provisioning request

Status: **BLOCKED — no approved company tenant or test registrations supplied.**
Do not infer a tenant from email, DNS, an existing login session, or public
`common` metadata. First confirm the company tenant GUID and the administrator's
authority to create the following resources. This handoff is not authority for
the Arlen agent to mutate a tenant or publish research data.

## Requested isolated configuration

Intended resource: `https://mcp.invitoep.com/research/mcp`.

| Setting | Required test configuration |
| --- | --- |
| API registration | `Research MCP Test API`; single tenant, `signInAudience=AzureADMyOrg`; separate from clients |
| Access tokens | `api.requestedAccessTokenVersion=2`; expected `ver=2.0` |
| Audience | API application's GUID, **not** the client GUID, Graph audience, or public resource URL |
| Application ID URI | `api://<RESEARCH_API_APPLICATION_GUID>` |
| Delegated scope | `Research.Read`, admin consent only; full scope `api://<RESEARCH_API_APPLICATION_GUID>/Research.Read` |
| Permissions | Delegated read-only; no daemon roles/service-principal grants; `allowApplicationPermissions=false` |
| Assignments | Require assignment on API and each client enterprise application; explicitly assign Daniel and his colleague using administrator-confirmed directory identities |
| Consent | Add the research delegated API permission to each client and grant required tenant admin consent; consent does not replace assignments |
| Client renewal | Request qualified research scope and `offline_access`; retain company MFA/Conditional Access |
| Arlen identity | Verified `tid:oid`; enforce the two test identities and approved client IDs in application policy, not email |

If user roles are selected, define a user-only `Research.TestReader` API role,
assign both test users, and require it consistently in REST/MCP. Do not create
an application permission with that name. Confirm assignments on all four
enterprise applications; verify a third, unassigned test identity is denied.
[Microsoft assignment/consent guidance](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/grant-admin-consent).

## Three separate interactive clients

| Client | Registration | Redirect registration |
| --- | --- | --- |
| Claude Team Desktop/Cowork remote connector | Single-tenant confidential **Web** client | `https://claude.ai/api/mcp/auth_callback` |
| Claude Code | Single-tenant **Mobile and desktop / public** client; no secret | `http://localhost:8765/callback` |
| Codex CLI | Single-tenant **Mobile and desktop / public** client; no secret | Exact callback printed for the canonical service URL by the installed client; listener port 8766; preserve the callback ID suffix when present |

For Claude Team, an authorized Team administrator configures the remote custom
connector's client ID/secret. Store its secret directly in approved storage and
the supported connector UI; do not send it to Arlen or paste it in chat.
For both CLIs, use authorization code with S256 PKCE; disable implicit flow and
password/direct-grant flows. Do not configure a native-client secret or SPA
redirect to resolve a registration error.

Claude Code registration command:

```bash
claude mcp add --transport http --client-id '<CLAUDE_CODE_CLIENT_GUID>' \
  --callback-port 8765 research https://mcp.invitoep.com/research/mcp
```

For Codex, set `mcp_oauth_callback_port = 8766` at the top of its configuration,
then, **once an approved synthetic test endpoint is available**, run:

```bash
codex mcp add research --url https://mcp.invitoep.com/research/mcp \
  --oauth-client-id '<CODEX_CLIENT_GUID>'
```

Register the exact displayed callback before login; also capture the actual
listener port. The suffix depends on the service URL and issuer metadata, so
no guessed callback is an acceptable final registration. If the displayed URL
is portless, verify the actual authorization redirect with the configured 8766
listener. If using an explicit URL port, configure the same callback listener
port. Entra's HTTP `127.0.0.1` registration may require manifest/API editing.
See [the runbook](../OAUTH_RESOURCE_SERVER.md) for sources and client commands.
Returning “localhost” or “/callback” alone is not sufficient.

## Provisioning and exposure gates

1. Return the non-secret configuration below. Arlen will inspect the **actual
   tenant** metadata for PKCE advertisement and other discovery requirements.
2. Supply an approved HTTPS synthetic-only test endpoint reachable by hosted
   Claude. The canonical route may temporarily terminate at the isolated
   synthetic app; it must have **no connection to research data or port 3122**.
   Keep research-data forwarding disabled. If a different test URL is required,
   approve it explicitly and re-register Codex's callback for the final URL.
3. Test actual clients with their secure credential stores: discovery, browser
   MFA, authorization code/S256, exact redirects, qualified scope/resource,
   expected API audience, initialize/list/call, denial, automatic renewal,
   forced reauthentication and local suspension. Never copy tokens into tests.
4. Resolve the observed metadata gap before asserting a supported path. A
   metadata-only adapter is not yet proven for all three clients; a broker
   requires a separate identity-service decision. Neither is being deployed.
5. Keep public research-data routing disabled until all actual client flows and
   downstream data policies pass, followed by separate deployment approval.

## Forward to DevOps (user-provided request)

Coordinate with the Arlen agent to provision an Entra test configuration for our research MCP.

First confirm our company tenant and your authority to create app registrations. Use a single-tenant API registration, separate client registrations, delegated read-only access, and explicit test-user assignments for Daniel and his colleague.

Follow Arlen’s client-specific registration instructions. Configure any client secrets directly in approved secret storage; do not paste them into chat.

Return only:

- Tenant ID
- API application ID / expected audience
- Access-token version
- Fully qualified exposed scope names
- Each client ID, registration type, and exact redirect URIs
- Confirmation of test-user assignments and required consent

Keep public research-data routing disabled until authentication acceptance passes.

Delivery status: prepared for forwarding. No external DevOps recipient/session
is available to the Arlen agent in this workspace; no delivery is claimed.
