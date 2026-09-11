# StateCompulsoryPoolingAPI OAuth adoption handoff

Status: implementation in Arlen; awaiting downstream adoption and live client
acceptance. The downstream checkout and approved tenant configuration were not
available in this workspace. The pilot facts below come from the task brief,
not inspection or modification of the running service.

## Existing and proposed boundaries

The research pilot on `iep-softwaredev`, loopback port 3122, uses scoped HS256
bearer credentials with a revocation registry. Its six tools are `search`,
`fetch`, `research_documents`, `research_document`, `research_segments`, and
`research_coverage`. Preserve their application behavior and result schemas.
The proposed public entry is `https://mcp.invitoep.com/research/mcp`.

Arlen supplies verification, a stable principal, shared scope/role checks,
per-request authorization hooks, resource discovery and MCP challenges. The
API owns tool grants, user/client assignments, record filtering and suspension.
DevOps owns tenant registrations, network boundaries, TLS and routing. Nothing
in this change deploys these components or modifies the pilot.

## API agent: exact adoption sequence

1. Adopt the Arlen commit identified in `OAUTH_IMPLEMENTATION_REPORT.md` / the
   accompanying handoff. Initialize its existing submodules and use the supported
   clang-based GNUstep toolchain. First run upstream evidence:

   ```bash
   source tools/source_gnustep_env.sh
   make oauth-check mcp-check
   ```

2. In a **new local/test application configuration**, choose explicit
   `mcp.oauth` configuration from `examples/mcp_app/entra.example.json`, set
   `mcp.path=/research/mcp`, the intended canonical public URL, tenant, token
   version and research-only API audience. Keep session and CSRF disabled for
   this bearer API. Remove the pilot bearer secret from this instance. Do not
   broaden issuer/audience acceptance to make old tokens work.
3. Integrate a shared application access service through
   `initWithConfiguration:documentLoader:nil authorizationPolicy:...` and assign
   it to `mcp.resourceServer` before plugin installation. Use the verified
   `tenantID:objectID` key; map existing records explicitly, never by email.
   Maintain separate delegated and daemon grants. Default daemon access off.
4. Register all six existing tool names. Prefer `registerRouteTool` for existing
   REST actions and keep their `requiredScopes`, `requiredRoles`, guards, and
   record checks on the REST route. For a custom handler declare the same
   permission contract and use the same application access service. MCP startup
   rejects tools whose backing route is outside `protectedPaths`.
5. Review and approve a permission matrix. A minimal read-only starting proposal
   is `Research.Read` for all six tools, plus record restrictions below. This
   table is a proposal, not an assertion about existing pilot permissions:

   | Tool | Application data policy |
   | --- | --- |
   | `search`, `research_documents` | Filter results and counts to allowed records before serialization/pagination |
   | `fetch`, `research_document` | Resolve identifier then authorize the actual record, including aliases/redirects |
   | `research_segments` | Authorize the parent document and each returned segment boundary |
   | `research_coverage` | Define whether aggregate corpus counts may disclose restricted records; filter if required |

   Add narrower scopes only when application requirements justify them. Use
   short Entra `scp` values in route checks, qualified API scopes in discovery.
6. Extend the local revocation registry with a distinct subject/client suspension
   namespace for Entra principals. Keep pilot token IDs separate; do not treat
   a JWT identifier as the Entra user key. Consult the store on every protected
   request; unavailable policy storage must deny protected work. A still-valid
   Entra JWT must lose access immediately when locally suspended.
7. Add downstream fixtures for each tool and underlying REST endpoint: allowed
   user, missing scope, missing role, suspended subject, excluded record, daemon
   denial, and other-service audience. Confirm search, counts and pagination do
   not reveal excluded records. Confirm old HS256 credentials fail on the new
   instance, including with a previously established session.
8. Produce an adoption PR with configuration placeholders, fixture results and
   remaining live acceptance items. Do not change port 3122 or publish routes.
   Record downstream status as awaiting deployment/acceptance until performed.

No API token should be forwarded to Graph or another MCP service. Arlen's
route-backed MCP calls dispatch inside the same application/resource, retaining
its original credentials. If application code calls an unrelated API, acquire
that API's own credential using a separately reviewed flow.

## DevOps agent: exact preparation and approval sequence

1. Read [the administrator runbook](../OAUTH_RESOURCE_SERVER.md). Obtain approval
   for a test tenant/API registration and three client registrations. Supply
   only tenant GUID, API audience/version, scope names, client IDs, callback
   URIs and assignment decisions to the API agent. Configure secrets directly
   in the hosted client's supported secret storage.
2. Resolve the observed PKCE metadata compatibility gate from the runbook
   before promising direct sign-in. Inspect approved tenant metadata for
   `code_challenge_methods_supported`; pursue a supported issuer-preserving
   metadata remedy before proposing a maintained broker. Neither component is
   supplied by this change. Configure single-tenant research access, test users/group, consent, roles,
   assignment requirements and company MFA. Keep application permissions off
   unless an explicit daemon use case and allowlist are approved.
3. Register hosted Claude's exact Web callback
   `https://claude.ai/api/mcp/auth_callback`; Claude Code's public callback
   `http://localhost:8765/callback`; and the exact callback printed by Codex
   preregistration with listener port 8766 (including any path suffix). See the
   runbook for Entra's HTTP IP-loopback registration restriction.
4. Prepare, but do not publish without separate deployment approval, routes for
   `/research/mcp` and
   `/.well-known/oauth-protected-resource/research/mcp`. Preserve both paths to
   the new backend. Plan the network hop explicitly: a gateway on another host
   cannot reach `iep-softwaredev` loopback directly. Use the organization's
   approved private routing/TLS arrangement, never a public backend listener.
5. Prepare a separate Entra-only backend instance on an approved unused private
   port. Do not reuse the live pilot's port 3122 during evaluation. Configure
   canonical resource/audience independently of Host and proxy headers. Allow
   backend outbound access to the configured Entra discovery/JWKS hosts; keep
   the GNUstep TLS CA trust store and system clock operational.
6. After separate deployment approval, execute the runbook's entire live
   acceptance checklist for Claude Team Desktop, Cowork, Claude Code and Codex.
   Record exact client versions, callback shape, scope/audience match booleans,
   renewal and forced reauthentication evidence. Do not store bearer tokens,
   refresh tokens, authorization codes, callback queries, or research content.
7. Test gateway bypass against the private backend with approved test tooling:
   missing, expired, other-resource and retired-pilot credentials must fail;
   valid research credentials remain subject to identical data policy.

## Coexistence, retirement and rollback

Coexistence is **separate listeners/configurations**. The existing pilot remains
private with its current credentials and revocation registry while the new
instance requires Entra only. Never put an HS256 fallback on the public route,
and never translate arbitrary pilot tokens into Entra principals. If a user
needs both during the transition, keep each client's server configuration
explicitly named and tied to its own URL/credential flow.

Before retirement, confirm all target clients renew credentials without manual
token copy or SSH tunnels, all six tools have data-policy regression coverage,
and support staff can suspend a subject immediately. Inventory remaining pilot
callers without capturing their credentials. Then, under a separate approved
change, revoke outstanding pilot tokens, remove their distribution paths,
stop the old listener and remove its verifier secret. Retain minimal revocation
and audit records according to company retention policy.

Rollback removes/disables the new public route and restores the prior private
service arrangement under deployment approval. It must never relax the public
Entra-only credential requirement. Downstream and DevOps agents own their
rollout/rollback confirmation; upstream fixture tests do not close that work.

## Follow-up: readiness and deployment ownership

The intended company URL above belongs only to the downstream application. Arlen
requires no hostname or deployment. Use [the exact administrator request](ENTRA_TEST_ADMIN_HANDOFF.md)
and [client acceptance matrix](ENTRA_MCP_INTEROPERABILITY.md); no actual tenant
configuration has been supplied. Keep public **research-data** forwarding disabled.
An approved synthetic-only endpoint can be used for client acceptance without any
connection to port 3122 or research storage.

API agent: set `refreshOnRequest=false`, `preflightOnStart=true` on the existing
resource-server configuration. Start one dedicated in-process maintenance worker
that calls `refreshSigningKeysWithError:` every 30 seconds with the default
300-second cache age; do not schedule this on the serialized dispatcher. Stop/join
it during shutdown. Use the same module `resourceServer` instance. Wire `isReady`
to a private application readiness endpoint returning 503 when false; the stock
`/readyz` does not automatically consult it. Scope the endpoint outside protected
data prefixes and protect its network access with application/DevOps policy.
Readiness reports key-cache freshness, not end-to-end sign-in or all key IDs.

DevOps agent: probe that application readiness route, allow bounded outbound
HTTPS to application-configured issuer/JWKS destinations, and budget startup for
two fetch deadlines plus scheduling overhead. Preserve canonical resource metadata
and challenges at both existing handoff paths. TLS/proxy/Host policies remain
application/gateway configuration; no framework hardcoded company trust settings
were introduced. A gateway on another host needs approved private connectivity
and cannot address the pilot's loopback remotely. No broker or adapter is approved
for deployment by this change; the maintained-broker PoC contract is only a
contingency proposal in the decision document.
