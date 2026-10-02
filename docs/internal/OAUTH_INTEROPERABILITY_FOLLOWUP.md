# OAuth interoperability / operational follow-up report

Baseline: `64cb92fa9f31e656189e80d0bccbfb2e93c41398`. Independent downstream review
reported its 14 OAuth tests, 16 MCP tests and both HTTP checks passed. That
accepts isolated framework integration; it does not establish live sign-in.
Identify this follow-up's commit using `git log -1 --format=%H -- docs/internal/OAUTH_INTEROPERABILITY_FOLLOWUP.md`.

## Completed framework work

- Added `refreshSigningKeysWithError:` for explicit bounded single-flight
  maintenance and `isReady` for a no-network freshness check.
- Added opt-in `preflightOnStart` and `refreshOnRequest=false`. The recommended
  serialized-runtime path warms keys before startup, refreshes on one dedicated
  application worker, and rejects missing/unknown/expired keys immediately on
  dispatch. No worker or deployment is implicitly created by Arlen.
- Moved network retrieval outside the validation monitor, retaining a separate
  fetch lock, cooldown, bounded documents/key count and strict original expiry.
  Existing synchronous behavior remains the default for compatibility.
- Added outage/preflight, stalled-refresh/rotation/readiness and latency tests;
  added an offline synthetic discovery audit to the existing OAuth CI target.
- Kept issuer, tenant, audience, scopes, public resource and proxy trust entirely
  application configuration. Reusable Entra examples/docs now use placeholders,
  including the application scope. Company-specific details are confined to
  downstream handoffs. Arlen requires no public hostname or identity deployment.

## Validation evidence

- `make oauth-check mcp-check`: 17 OAuth methods and 16 MCP methods passed, both
  real loopback HTTP example checks passed, eight synthetic discovery cases passed.
- Controlled latency run: synchronous cold validation **0.300680 seconds** with
  two 150-ms loader delays; existing/unknown/expired-key checks plus readiness
  **0.000647 seconds** while a maintenance fetch was deliberately held in flight.
  These are local fixture measurements, not production latency percentiles or
  real provider timings. Production maintenance still has two 5-second network
  timeouts plus scheduler overhead; requests in maintenance mode do not wait.
- Public Entra discovery fetched read-only and audited offline: issuer-template,
  HTTPS endpoints and code response checks passed; S256 advertisement check
  failed (audit exit 1 as expected). No runtime was configured to trust common.
- `make test-unit`: 712 test methods across 98 classes passed.
- `make docs-api docs-html` and `make ci-docs`: API generation, documentation
  consistency/navigation checks and HTML quality gate passed.

The fixtures use ephemeral test keys; no live OAuth token, password, authorization
code, token-expiry editing or manually copied access token is acceptance evidence.
`isReady` checks snapshot freshness, not all possible kids or actual sign-in;
stock `/readyz` is unchanged. Operators must wire application readiness and the
maintenance worker. Omitting maintenance causes eventual fail-closed unavailability.

## Downstream decision and remaining gate

[Decision and client matrix](ENTRA_MCP_INTEROPERABILITY.md): no proven working
all-client path yet. Direct Entra remains the first approved-test candidate;
metadata-only adaptation is unproven for hosted Claude and Codex. A maintained
Keycloak federation PoC is specified as a contingency, including issuer/audience,
RS256 at+jwt/client/permission claim mapping, ownership and revocation limits.
No adapter, broker or production identity service was deployed or approved.

The public metadata omission is an observed **specification incompatibility**;
it is not a recorded company-client failure. All actual-client flow rows remain
**BLOCKED**, not failed or passed: company tenant/API/client registrations,
exact callbacks, approved assigned identities and synthetic HTTPS reachability
are unavailable. Primary documentation establishes client features; CLI versions
only identify installed binaries. Neither proves sign-in or renewal.

Next action: an authorized administrator must confirm the tenant and provisioning
authority, supply the non-secret registration/assignment/consent information in
[the administrator handoff](ENTRA_TEST_ADMIN_HANDOFF.md), and approve synthetic
HTTPS testing. Keep public research-data routing disabled. The exact DevOps
message is included there for forwarding; no DevOps session/recipient was
connected, so no delivery is claimed.

The [API/DevOps adoption handoff](STATE_COMPULSORY_POOLING_OAUTH_MIGRATION.md)
now specifies worker scheduling, readiness integration, private connectivity,
gateway metadata paths and the boundary between synthetic acceptance and
research-data rollout. Port 3122, tenant resources and public access are unchanged.
Unrelated local changes are preserved. The overall downstream seamless-sign-in
objective remains incomplete until every actual client flow passes.
