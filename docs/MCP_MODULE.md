# MCP Module

Arlen's optional `mcp` module exposes explicitly registered application tools over
Streamable HTTP. It contains no domain services, search engine, or application
endpoint assumptions. Installing or linking it does not expose any routes:
`mcp.enabled` defaults to `NO`. OpenAPI inclusion and HTTP method never opt a
route in.

## Supported protocol

The supported revision is **2025-11-25**, with JSON responses over Streamable
HTTP at `/mcp` by default. The module implements `initialize`,
`notifications/initialized`, `ping`, `tools/list`, and `tools/call`. Initialization
returns that version even when the client proposes another version. Clients
that cannot use it must disconnect. Only the `tools: {}` capability is
advertised. See the official [lifecycle specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle).

This is a stateless implementation of the 2025 transport: no session ID,
per-client capability store, sticky routing, or initialized-state gate. Clients
must initialize and send the initialized notification; lifecycle ordering is
client-owned. There are no server-to-client requests, so client capabilities
are not consumed. The newer [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/changelog)
changes the handshake and wire contract and is **not supported**.

POST requests require `Content-Type: application/json` and an `Accept` header
accepting both `application/json` and `text/event-stream`. Subsequent requests
must carry `MCP-Protocol-Version: 2025-11-25`; missing subsequent versions and
unsupported header versions return HTTP 400. JSON-RPC responses use HTTP 200
and JSON. Accepted notifications and unsolicited client responses receive
HTTP 202 with an empty body. Notifications never invoke tools. GET and DELETE
return 405: there is no SSE stream or session to terminate. See the official
[transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

Unsupported features are not advertised: SSE, resumability, server-initiated
messages, tasks, progress, active cancellation, resources/list/read,
subscriptions, prompts, logging control, completion, sampling, elicitation,
stdio, legacy HTTP+SSE, and dynamic catalog updates. Cancellation notifications
are accepted but cannot interrupt synchronous application handlers. The catalog
is one bounded, sorted page; supplying a cursor returns an invalid-params error.

## Install and enable

In an application using Arlen's module tooling:

```bash
/path/to/Arlen/bin/arlen module add mcp
/path/to/Arlen/bin/arlen module doctor --json
```

Configure the app's `config/app.plist`:

```plist
mcp = {
  enabled = YES;
  path = "/mcp";
  providerClass = "CatalogMCPProvider";
  requiredScopes = ("catalog:read");
  allowedOrigins = ();
  maxOutputBytes = 262144;
  requestsPerMinute = 120;
};
```

The provider implements `ALNMCPToolProvider` and registers tools through the
module passed to `registerToolsWithMCP:application:error:`. It may register
application routes there, or reference named routes that will exist by startup.
Arlen resolves route references in the module's startup hook. Return `NO` and
propagate errors on every registration failure.

For a programmatic app, create one `ALNMCPModule`, register tools, then call
`[app registerPlugin:mcp error:&error]` before `startWithError:`. Use either
module loading or programmatic installation, not both. Do not register tools
after installation. The module instance belongs to one application; there is
no process-global registry.

The complete runnable example is [examples/mcp_app](../examples/mcp_app/README.md).
It exposes a catalog item route and a service-backed catalog summary. Both are
explicitly read-only.

## Register route-backed tools

```objc
#import "ALNMCPModule.h"

NSDictionary *annotations = @{
  @"readOnlyHint": @YES, @"destructiveHint": @NO,
  @"idempotentHint": @YES, @"openWorldHint": @NO
};
BOOL ok = [mcp registerRouteTool:@{
  @"routeName": @"catalog_item",
  @"name": @"catalog.item.v1",
  @"description": @"Read one catalog item",
  @"annotations": annotations,
  @"inputSchema": @{
    @"type": @"object",
    @"properties": @{ @"item": @{ @"type": @"string" } },
    @"required": @[ @"item" ]
  },
  @"argumentMapping": @{
    @"item": @{ @"source": @"path", @"name": @"id" }
  }
} transform:nil error:&error];
```

`routeName` identifies exactly one existing route. An omitted tool name uses
its operation ID, then its route name. Description defaults to its summary.
Explicit names are recommended for contracts that must survive HTTP API
renaming. Names are case-sensitive, 1–128 ASCII letters/digits/`_`/`.`/`-`.
Duplicates and invalid registrations fail startup. Route metadata must be
configured before startup and must not change while the application is running.

Every registration must declare all four boolean annotations shown above.
They describe effects and external-system interaction; they neither grant
permission nor trigger confirmation. GET does not imply safety. App authors
remain responsible for accurate metadata, consent, idempotency, and auditing.

Input/output schemas default to the route's request/response schema when
present. Supply explicit schemas to decouple the public tool contract from an
HTTP representation. Route tools inherit permissions, roles, assurance,
authentication-age limits, guard, and policies from the actual route; permission
fields on a route-tool definition are rejected rather than ignored.

### Argument mapping

Mapping is declarative: every input property maps to exactly one `{source,name}`
destination. Supported sources are `path`, `query`, and `body`. Without
`argumentMapping`, each route request-schema property must declare an explicit
supported `source`; the argument and destination names are identical.

- Path/query arguments must be strings, numbers, integers, or booleans. Arrays
  and nested objects are supported only in JSON body mappings.
- Path arguments must be required, cover every `:parameter`, and match the
  route exactly. Empty values, dot segments, `/`, `%`, backslash, `?`, and `#`
  are rejected. Values are percent-encoded as single HTTP path segments; route
  params retain Arlen's normal HTTP path representation.
- Query names/values are percent-encoded; booleans become `true`/`false`.
- Body mappings form a JSON object. There are no form, multipart, whole-body,
  header, cookie, credential, identity, or arbitrary-URL mappings.
- Unknown arguments, unmapped properties, duplicate destinations, wildcard or
  format-constrained routes, and unsupported methods fail validation. Supported
  route methods are GET, POST, PUT, PATCH, DELETE. Method support is unrelated
  to side-effect classification.

The resulting request uses the original HTTP credentials, cookies, Origin,
policy headers, peer addresses, and scheme. Content framing is rebuilt;
`Accept` and `Content-Type` become `application/json`. MCP transport headers are
removed. A fresh context is created: claims and session stash are never copied
from arguments or the outer context. Existing request-schema coercion and
validation still run on the mapped HTTP request.

### Results and transformation

Without a transform, a successful route response must contain a JSON object;
it becomes `structuredContent`. A transform receives the **finished**
`ALNResponse`, including response middleware, and returns an MCP result:

```objc
ALNMCPResponseTransform transform = ^NSDictionary *(ALNResponse *response,
                                                       NSError **error) {
  NSDictionary *envelope = [ALNJSONSerialization
      JSONObjectWithData:response.bodyData options:0 error:error];
  return envelope ? @{ @"structuredContent": envelope[@"data"] } : nil;
};
```

Use this to unwrap an app-owned envelope, omit private fields, or create a
stable result contract. Transforms run only after HTTP 2xx, within the response
size limit. They cannot turn an auth denial into success. Redirects are not
followed. File and streaming responses are unsupported.

## Register service-backed tools

```objc
BOOL ok = [mcp registerTool:@{
  @"name": @"catalog.summary.v1",
  @"description": @"Summarize the local catalog",
  @"annotations": annotations,
  @"inputSchema": @{ @"type": @"object" },
  @"outputSchema": @{
    @"type": @"object",
    @"properties": @{ @"count": @{ @"type": @"integer" } },
    @"required": @[ @"count" ]
  },
  @"requiredScopes": @[ @"catalog:read" ],
  @"requiredRoles": @[ @"reader" ],
  @"policies": @[ @"internal_clients" ]
} handler:^NSDictionary *(NSDictionary *args, ALNContext *context,
                           NSError **error) {
  return @{ @"structuredContent": @{ @"count": @([catalog count]) } };
} error:&error];
```

Handlers compose app services directly. They receive validated arguments and a
fresh, authenticated application context. `requiredScopes`, `requiredRoles`,
`policies`, `minimumAuthAssuranceLevel`, and
`maximumAuthenticationAgeSeconds` configure the private invocation route.
There is no required public HTTP endpoint per tool. Private routes under
`/mcp/_tools/` reject ordinary HTTP callers even with valid credentials; only
an in-process request capability created by the module permits the handler.
Services must be safe for the application's concurrency model and enforce their
own object/tenant permissions where required.

## JSON Schema contract

MCP schemas use JSON Schema semantics, not an OpenAPI parameter object. This
release publishes a deliberately restricted subset compatible with JSON Schema
2020-12. It validates definitions at startup and values at invocation/result
time, without silently accepting unsupported assertions.

Supported keywords: `type`, `properties`, `required`, boolean
`additionalProperties`, `items`, `enum`, `description`, `title`, `minimum`,
`maximum`, `minLength`, `maxLength`, `minItems`, and `maxItems`. Supported types:
object, array, string, integer, number, boolean, null. Both roots must be objects.
Arrays need an item schema. Maximum schema depth is 32. Booleans and numbers
are distinct; no coercion/default insertion occurs during MCP input validation.
String lengths count Unicode scalar values.

Objects default to `additionalProperties: false` and this is included in the
published schema. Custom tool schemas may explicitly allow extra properties;
route tool inputs may not. Empty input schemas become closed empty objects.
Arlen route-property type shorthand and property-level boolean `required` are
normalized; top-level property `source` is used for mapping and removed from
the published schema. Use the explicit `properties` form for route schemas.

Unsupported mappings fail with an `Arlen.MCP` error: OpenAPI `nullable`, `$ref`,
`allOf`/`oneOf`/`anyOf`, type unions, schema-valued additional properties,
formats, defaults, coercers/transformers, and all other unlisted keywords. In
particular `nullable` is not silently dropped, and formats are not advertised
without validation. Supply an explicit supported schema and, if necessary, a
result transform; otherwise use a service tool with a simpler contract.

## Output and errors

Successful results may contain `structuredContent` (object) and `content`
(text and/or resource links). When an output schema exists, structured content
is required and validated. The module appends a text block containing the
serialized structured object for compatible clients. Resource links require
an absolute `uri` and nonempty `name`; optional string fields are `description`,
`mimeType`, and `title`. No resource is fetched by the framework. Resource links
do not advertise a resources API. See the official [tool-result specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).

`maxOutputBytes` defaults to 262144 (allowed: 1024–16777216). It bounds the
catalog at startup, the route response before transformation, and the final
serialized tool result including compatible text. The small JSON-RPC envelope
is additional. Oversized output becomes a tool error; it is never truncated
into invalid JSON. This is an output bound, not a memory quota on application
handlers. Input HTTP bodies are capped at 1 MiB by the module, in addition to
Arlen's server-level request limits.

Malformed JSON is `-32700`, malformed JSON-RPC/batches `-32600`, unknown methods
`-32601`, and unknown tools or malformed call envelopes `-32602`. Invalid tool
arguments, route denials/failures, exceptions, invalid results, and output
bounds return a normal result with `isError: true`. Denials expose only the HTTP
status; exception and NSError details are not sent to clients. Handlers may
return their own safe text error with `isError: true`; returning nil or setting
NSError produces a generic execution failure.

## Authentication, policies, and deployment

Authentication is mandatory on the MCP endpoint. The module accepts identity
established by application middleware/auth sessions, or invokes Arlen's bearer
verifier with `auth.bearerSecret`, `auth.issuer`, and `auth.audience`. Set issuer
and audience explicitly for machine clients. Caller-provided tool arguments
and identity headers do not establish identity. Every call traverses the outer
MCP request and a full inner dispatch, including authentication, authorization,
guards, middleware, and request/response contracts. The constrained dispatcher
rejects mounted-app delegation and any route mismatch before an alternate
controller can execute.

The MCP endpoint accepts `requiredScopes`, `requiredRoles`, and named `policies`
in its config. Custom tools need their own service permissions. Route-backed
tools retain the original route's permissions and path-based policies. Custom
tools have private paths, so attach policies by name instead of relying on an
unrelated HTTP route's path-prefix rules. Catalog visibility is shared among
authenticated endpoint users: listing a tool never grants permission to call
it. Use endpoint permissions if catalog metadata itself is sensitive.

CSRF/session middleware remains active. Session clients must provide their
valid cookie and CSRF header on MCP POSTs, even for read-only tools. A bearer
header does not automatically bypass an app's CSRF policy. The example uses a
stateless bearer-only app with sessions/CSRF explicitly disabled. Do not disable
CSRF globally in a mixed browser app merely to make an MCP client work.

Arlen's standard response-envelope middleware is disabled only in MCP protocol
and private service contexts via `ALNResponseEnvelopeDisabledStashKey`. Ordinary
route responses retain their envelopes and can be transformed. App-specific
response rewriters must preserve JSON-RPC on the MCP endpoint. Middleware may
run twice per tool call; this includes app rate limits, audit logs, and metrics.
Inner session/cookie/header mutations are not propagated to the outer response:
authentication/session-management routes are unsuitable tool candidates.

MCP resource credentials authorize access to this application. Downstream API
credentials belong in application services and secret stores; never forward an
MCP token to a different resource audience. This module does **not** implement
the optional MCP OAuth discovery/authorization flow (protected-resource metadata,
client registration, PKCE, or token issuance). Configure credentials explicitly
in clients. Apps needing automatic OAuth must supply a conforming resource/auth
integration; existing login UI alone does not provide it. See the official
[authorization specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

All incoming Origin values are denied unless exactly listed in `allowedOrigins`;
no Origin is accepted for native clients. Configure exact scheme/host/port
values, not wildcards. Bind development to loopback. Deploy behind TLS with
explicit Host/Origin allowlists and trusted-proxy settings as described in
[Deployment](DEPLOYMENT.md). Do not cache MCP responses. The module applies an
Arlen rate limiter to the MCP endpoint (120 requests/minute per peer by default,
`requestsPerMinute` range 1–100000); app limits also apply. Multi-worker/global
quotas require an ingress/shared limiter. Set HTTP request limits and service
backend deadlines. Synchronous handlers are not forcibly interrupted on client
disconnect or timeout. No MCP session storage is required across propane workers;
propane accessories retain their normal meaning and defaults.

## Verification and adoption

```bash
source tools/source_gnustep_env.sh
make mcp-check
```

This runs the focused XCTest-compatible suite through the vendored runner and
builds/tests the example over real HTTP. The suite also runs in ordinary unit
tests. Linux CI explicitly builds and exercises the optional example.

An independent client check is available with the official Python SDK:

```bash
python3 -m venv /tmp/arlen-mcp-client
/tmp/arlen-mcp-client/bin/pip install 'mcp==1.26.0'
/tmp/arlen-mcp-client/bin/python tools/mcp/check_client.py --sdk
```

Consumer adoption is explicit: update the application's Arlen pin only after
review, vendor/install the module, register supported schemas and tools,
configure authentication/policies, and revalidate under the consumer's actual
middleware and proxy setup. No consumer pins, deployments, or domain endpoints
are modified by this framework feature.

This module requires the Arlen revision containing
`dispatchRequest:requiringRoute:` and `ALNResponseEnvelopeDisabledStashKey`.
It is not a drop-in source module for older pinned Arlen checkouts. The existing
framework `0.1.0` version does not distinguish those commits, so the module
manifest's semver check alone is insufficient; use the tested implementation
commit recorded in the integration handoff.
