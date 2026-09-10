# MCP module implementation contract

Status: implemented as an optional first-party module. This document records the
architecture boundary; application instructions live in `docs/MCP_MODULE.md`.

## Architecture decisions

- `modules/mcp` owns JSON-RPC, the selected MCP revision, tool registration,
  schema normalization/validation, HTTP adaptation, and result bounds.
- App providers own tool selection, service composition, data access, permission
  choices, response transformation, and downstream credentials. No consumer
  route names or research-domain behavior are framework contracts.
- A per-application registry freezes during `applicationWillStart:error:`.
  Startup rejects collisions and unsupported schemas/mappings. No OpenAPI scan
  or method-based exposure is performed.
- Both route and custom tools use one `tools/call` implementation and one
  result validator. The custom path uses a private request capability and a
  normal route so Arlen's middleware and auth contracts still apply.
- `dispatchRequest:requiringRoute:` is the narrow core addition. Ordinary
  dispatch delegates with nil and retains its existing behavior. Constrained
  dispatch rejects mounts, built-in endpoints, and a mismatched resolved route
  before invoking an alternate controller. It never invokes a controller
  directly or copies a caller's claims into a new context.
- MCP and private-handler contexts opt out of the normal response envelope.
  This is representation control only; auth and policy middleware remain.
- Transport is stateless JSON-response Streamable HTTP, protocol 2025-11-25.
  No negotiated client features are used, session state is not retained, and
  capability output advertises tools only. The 2026 handshake changes are
  intentionally outside this supported version.

## Verification contract

`MCPModuleTests` is included by normal unit source discovery. `make mcp-check`
adds the real HTTP example probe and is explicitly called in the existing
Linux quality job. The probe checks initialization, notifications, listing,
both invocation paths, JWT resource-audience binding and other auth denials.
`--sdk` additionally tests the official Python MCP SDK 1.26.0. No new CI lane or
branch-protection check name is introduced.

The focused suite covers schema definitions and values, registration failures,
argument/result transformations, explicit side-effect declarations, default
non-exposure, auth/scope/role denials, session+CSRF, guard and middleware parity,
source-IP policies and forwarding spoofing, custom assurance/named policies,
rate limiting, output bounds, private invocation gates, and alternate dispatch.

## Deliberately deferred

Full JSON Schema, OAuth discovery and issuance, newer MCP revisions, SSE,
server-to-client features, progress/cancellation, dynamic catalogs/pagination,
streaming results, session-changing tools, and mounted-application route tools.
These require explicit future compatibility work and must not be advertised.
Consumer adoption, deployment, and consumer pin changes belong to the consumer.
