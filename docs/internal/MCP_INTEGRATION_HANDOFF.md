# MCP integration handoff

Tested implementation commit: **`acf52654e30b9176fa18aa1f4a589398414aa102`**.
The following documentation-only commit adds this handoff; the implementation
ref above contains the complete code, tests, example, and CI changes.

## Verification

- clang/GNUstep under `/usr/GNUstep`, repo-vendored tools-xctest runner.
- `make test-unit`: **695 methods across 97 classes passed**, including **16
  MCP tests**.
- Focused MCP suite, real HTTP example probe, and official Python MCP SDK
  **1.26.0** initialization/list/call/output-schema/error checks passed.
- Real HTTP tests verified JWT signature, expiry, resource audience, scope,
  and Origin denials. Session/CSRF, role, assurance, guard, middleware, and
  source-IP policy parity are covered by the focused suite.
- Module add/doctor passed in a temporary application.
- `make docs-api docs-html ci-docs` passed. The existing Linux quality workflow
  now runs `make mcp-check`; no new required-check name is introduced.
- No consumer checkout, Arlen pin, deployment, or remote branch was changed.

## Enable and register

After deliberately adopting the implementation commit (or a descendant), vendor
`mcp` with `arlen module add mcp`. Set `mcp.enabled = YES` and configure a
`providerClass` implementing `ALNMCPToolProvider`, or install programmatically:

```objc
// app config contains mcp = { enabled = YES; }; and real auth configuration.
ALNMCPModule *mcp = [ALNMCPModule new];
NSDictionary *effects = @{
  @"readOnlyHint": @YES, @"destructiveHint": @NO,
  @"idempotentHint": @YES, @"openWorldHint": @NO
};
BOOL ok = [mcp registerRouteTool:@{
  @"routeName": @"catalog_item", @"name": @"catalog.item.v1",
  @"annotations": effects
} transform:nil error:&error];
ok = ok && [mcp registerTool:@{
  @"name": @"catalog.summary.v1", @"annotations": effects,
  @"inputSchema": @{ @"type": @"object" },
  @"requiredScopes": @[ @"catalog:read" ]
} handler:^NSDictionary *(NSDictionary *args, ALNContext *ctx, NSError **err) {
  return @{ @"structuredContent": [catalogService summaryForContext:ctx] };
} error:&error];
ok = ok && [app registerPlugin:mcp error:&error];
// Abort startup if !ok; otherwise call startWithError: normally.
```

These catalog names are examples only. Consumer endpoint names and services
are entirely consumer-owned. The runnable non-pooling example is
`examples/mcp_app/main.m`; full setup/contracts are in `docs/MCP_MODULE.md`.

## Wire, auth, and mapping contract

- MCP **2025-11-25**, stateless JSON-response **Streamable HTTP**, `/mcp` by
  default. Initialize and send initialized notification; subsequent requests
  carry the negotiated protocol header. Only tools capability is advertised.
- Authentication is mandatory. Existing Arlen bearer verification or trusted
  auth/session middleware establishes identity separately on both the outer
  MCP request and fresh inner invocation. Credentials/claims are never mapped
  from tool arguments. MCP resource tokens are not downstream credentials.
- Route-backed tools use full constrained dispatch: middleware, scopes/roles,
  assurance/age, guards, source-IP and named/path policies remain active.
  Alternate routes and mounted-app delegation fail closed. Custom tools use
  private capability-gated invocation routes; attach service policies by name.
- OpenAPI inclusion and HTTP method never expose a route. All four side-effect
  annotations are mandatory and descriptive, not authorization.
- Defaults reuse route operation ID/name, summary, and supported schemas.
  Explicit name/description/inputSchema/outputSchema keep a stable public tool
  contract. Argument mapping is `{argument: {source: path|query|body, name: field}}`;
  without an explicit map, request properties need explicit supported sources.
- Route HTTP 2xx JSON objects become structured results. An optional transform
  receives the completed response and returns an MCP result. Non-2xx responses
  cannot be transformed into success. Custom handlers return the same result
  shape. Output schemas are checked; JSON text is appended for compatibility;
  text/resource links are supported. Default output limit is 256 KiB.
- Tool execution/validation/authorization failures produce `isError: true`;
  malformed protocol requests and unknown methods/tools use JSON-RPC errors.
  Endpoint authentication/policy denials remain HTTP errors.

## Required consumer work and limitations

1. Keep implementing ordinary read-only APIs/services against the existing pin
   until the consumer explicitly adopts the new Arlen ref. **Do not silently
   bump StateCompulsoryPoolingAPI's pin.** This module needs the new constrained
   dispatch API and response-envelope key; existing `0.1.0` semver metadata alone
   cannot distinguish compatible commits.
2. Explicitly register chosen tools with accurate effects and permissions.
   Convert unsupported OpenAPI schemas or provide simpler explicit schemas.
   The supported JSON Schema subset is enumerated in the guide; nullable,
   references/composition, formats, defaults, and coercers are rejected.
3. Configure MCP resource issuer/audience and endpoint access. Existing consumer
   path/session/CSRF/policy middleware must be revalidated. Custom tools need
   named service policies; unrelated HTTP path-prefix policies do not magically
   attach to them. Middleware can run twice per call.
4. Supply configured credentials in the MCP client. This release does not
   implement OAuth discovery, registration, PKCE, or issuance. No SSE, tasks,
   active cancellation, resources API, dynamic catalogs, or 2026 protocol.
5. Configure TLS ingress, Origin/Host and trusted-proxy rules, request limits,
   shared production quotas, and backend deadlines. Synchronous service work
   is not interrupted when a client disconnects. Session-changing tools,
   streaming/file responses, and mounted-application route tools are unsupported.

Downstream adoption/revalidation remains pending and belongs to the consumer.
