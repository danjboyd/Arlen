# Read-only catalog MCP example

This small application exposes an existing named catalog route and a custom
summary tool backed by `CatalogService`. No domain code is in the MCP module.

From the Arlen repository root:

```bash
source tools/source_gnustep_env.sh
make mcp-example
export MCP_EXAMPLE_SECRET="$(openssl rand -hex 32)"
./build/mcp-example 3210
```

The server binds to `127.0.0.1`; MCP is at `/mcp`. Configure a client with an
HS256 bearer token signed with `MCP_EXAMPLE_SECRET`, `iss=mcp-example`,
`aud=arlen-catalog`, `scope=catalog:read`, a subject and a short future expiry.
This example does not issue tokens or provide an OAuth authorization server.
Do not expose it publicly without TLS and deployment configuration.

For an automated test that creates ephemeral credentials and cleans up its
server process:

```bash
source tools/source_gnustep_env.sh
make mcp-check
```

To also exercise the official independent MCP SDK, follow the commands in
[the module guide](../../docs/MCP_MODULE.md#verification-and-adoption).
Read [main.m](main.m) for complete registration code. The default route-to-result
mapping returns the catalog JSON object; custom summary results include an
output schema, compatible text, and a resource link.
