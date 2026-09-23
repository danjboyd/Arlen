# Getting Started

This guide gets you from a clean checkout to a running Arlen app without
pulling you through contributor-only release or CI material first.

If you are targeting macOS with Apple APIs rather than GNUstep, use
`docs/GETTING_STARTED_MACOS.md` first.

If you prefer a narrower path, see:

- `docs/GETTING_STARTED_QUICKSTART.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `docs/GETTING_STARTED_HTML_FIRST.md`
- `docs/GETTING_STARTED_DATA_LAYER.md`

For SQL ORM models, see the [ORM guide](ARLEN_ORM.md#sql-property-names).
Generated properties may use safe aliases for columns such as `State`; use the
manifest property names or `objectForColumnName:` with the original SQL name.
Legacy columns such as `Target ID` and `Unit/Well Notes` are supported without
schema renames; see [quoted identifiers](ARLEN_ORM.md#quoted-sql-identifiers).

## 1. Prerequisites

- a clang-built GNUstep toolchain
- `tools-xctest` (`xctest` command)

Initialize GNUstep in your shell. The repo helper also works with managed
toolchains that expose `GNUSTEP_SH` or `GNUSTEP_MAKEFILES`:

```bash
source /path/to/Arlen/tools/source_gnustep_env.sh
```

Run the bootstrap diagnostic first:

```bash
/path/to/Arlen/bin/arlen doctor
```

If you want structured output for automation:

```bash
/path/to/Arlen/bin/arlen doctor --json
```

For the known-good baseline, see `docs/TOOLCHAIN_MATRIX.md`.

## 2. Build Arlen

From repository root:

```bash
make all
```

This builds the main tools you will use first:

- `build/arlen`
- `build/boomhauer`
- `build/eocc`

## 3. Create Your First App

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
```

The full-mode scaffold gives you:

- `src/main.m`
- `src/Controllers/HomeController.{h,m}`
- `templates/layouts/main.html.eoc`
- `templates/index.html.eoc`
- `templates/partials/_nav.html.eoc`
- `templates/partials/_feature.html.eoc`
- `config/app.plist`

If you want the smallest possible app shape instead, see
`docs/LITE_MODE_GUIDE.md`.

## 4. Run the App

From app root:

```bash
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Then verify:

```bash
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/healthz
curl -i http://127.0.0.1:3000/openapi
```

`boomhauer` watches app files by default and rebuilds when inputs change.
Arlen reserves `/healthz`, `/readyz`, `/livez`, `/metrics`, and `/clusterz`
for built-in operability, so app routes should not reuse those paths.

## 5. Add One More Route

Prefer the generator-driven path for your second route:

```bash
/path/to/Arlen/bin/arlen generate endpoint Hello \
  --route /hello \
  --method GET \
  --template
```

That command:

- creates `src/Controllers/HelloController.{h,m}`
- wires the route into your app bootstrap
- creates `templates/hello/index.html.eoc`

Then verify:

```bash
curl -i http://127.0.0.1:3000/hello
```

For static route tables, you can also declare routes in `config/app.plist`
with the top-level `routes` array. Those entries call the same router APIs as
Objective-C route code, so matching, policies, reverse lookup, and route
inspection stay on one effective route table.

## 6. Common Next Commands

From app root:

```bash
/path/to/Arlen/bin/arlen routes
/path/to/Arlen/bin/arlen config --env development --json
/path/to/Arlen/bin/arlen check
```

Use `arlen routes` when you want to inspect registration order, route names,
and whether each route came from plist configuration or Objective-C code.

## 7. Choose the Next Guide

For login/logout flows that issue multiple cookies, see
[Response Headers and Multiple Cookies](RESPONSE_HEADERS.md).

- building JSON-first endpoints: `docs/GETTING_STARTED_API_FIRST.md`
- building server-rendered pages: `docs/GETTING_STARTED_HTML_FIRST.md`
- writing routes/controllers/middleware directly: `docs/APP_AUTHORING_GUIDE.md`
- configuring the app: `docs/CONFIGURATION_REFERENCE.md`
- adding first-party modules: `docs/MODULES.md`
- adding app-owned search resources after installing `jobs` + `search`:
  `arlen generate search Catalog` and `docs/SEARCH_MODULE.md`
- starting from the smallest app shape: `docs/LITE_MODE_GUIDE.md`
- generating plugins or service adapters: `docs/PLUGIN_SERVICE_GUIDE.md`
- generating frontend starter folders: `docs/FRONTEND_STARTERS.md`
- generating descriptor-first TypeScript models, validators, query/resource
  metadata, clients, and optional React helpers for a frontend app:
  `docs/GETTING_STARTED_API_FIRST.md`, `arlen typescript-codegen`, and
  `examples/react_typescript_reference/README.md`
- using Dataverse through the Web API: `docs/DATAVERSE.md`

## 8. Optional Dataverse Path

If your app needs Dataverse rather than the SQL migration/schema-codegen path,
use `docs/DATAVERSE.md`. The Dataverse surface is compiled in but
runtime-inactive by default, so apps that do not configure it do not pick up
extra startup work.

## 9. Contributor Notes

If you are working on Arlen itself rather than just building an app with it:

- `make test`, `make ci-quality`, and the broader confidence lanes remain the
  deeper project-level verification path
- `docs/DEPLOYMENT.md` covers the immutable release artifact workflow; current
  release payloads package migrations plus a prepared app binary so
  `framework/bin/propane` can run directly from the built artifact, and
  `arlen deploy list|dryrun|init|push|releases|release|status|rollback|doctor|logs`
  is the preferred operator-facing wrapper, including
  `config/deploy.plist.example`, checked-in `config/deploy.plist` targets, and
  SSH-backed target deploy flows
- `docs/DOCUMENTATION_POLICY.md` covers docs definition-of-done and quality
  expectations
- `docs/TESTING_WORKFLOW.md` covers the focused regression and confidence lanes

## Optional MCP tools

After ordinary routes and services work, install and explicitly enable the
[MCP module](MCP_MODULE.md) to expose selected capabilities to MCP clients.
OpenAPI inclusion does not expose tools. The [catalog example](../examples/mcp_app/README.md)
shows route and service registration with bearer authentication.

## OAuth-protected MCP and REST

Use the opt-in OAuth resource server and Entra preset for company API access.
See the [configuration and administrator runbook](OAUTH_RESOURCE_SERVER.md) for a protected
example, client preregistration, public discovery routes, and live acceptance
requirements. `mcp.oauth` requires OAuth bearer credentials without HS256/session
fallback; REST routes and MCP calls reuse Arlen scope, role, and application policies.

For serialized request runtimes, configure `refreshOnRequest: false` and
`preflightOnStart: true`, schedule key maintenance on an application worker, and
wire `isReady` into private readiness. The OAuth runbook documents the tradeoff;
framework tests require no tenant or public deployment.

OAuth metadata requests use certificate-chain and hostname verification with a 256 KiB response
limit, a five-second total deadline per document, and redirect/non-200 rejection.
GNUstep uses a bounded libcurl transport (development headers/library with TLS
and asynchronous DNS required; Debian/Ubuntu: `libcurl4-openssl-dev`). This works
on startup and maintenance threads without pumping application run-loop callbacks.
Apple retains Foundation transport. GNUstep metadata uses libcurl's CA configuration,
not GNUstep TLS user defaults. The general-purpose `ALNSynchronousURLRequest` helper
in `ALNHTTPCompat.h` also uses libcurl on GNUstep: it follows up to ten redirects
(`ALNSynchronousURLRequestFollowingRedirects` sets an explicit budget), returns HTTP
error statuses as responses, and reports transport failures with `NSURLErrorDomain`
codes such as `NSURLErrorTimedOut`. It does not consult shared cookie storage. Use a dedicated maintenance worker. Refresh errors distinguish discovery/JWKS
fetch failures, metadata validation failures, and cooldown. Diagnostics omit
URLs, credentials, response bodies, and custom loader error details.

For file-upload forms, use `[ctx.request uploadsForName:@"document"]` and `formParams`; see [Multipart Uploads](MULTIPART_UPLOADS.md) for examples and request limits.

## Background work in separate processes

Configure `ALNPostgresJobAdapter` before registering the jobs module when web
processes enqueue work for a separate worker. Apply its initial migration, use
the same database/namespace in each process, and launch `arlen jobs worker`.
The [Durable Jobs guide](DURABLE_JOBS.md) covers setup, transactional enqueue,
provider result methods, heartbeat pool capacity, shared queue controls, and
single-scheduler deployment. The default memory adapter is for development and
tests; file persistence alone does not provide worker crash recovery.

PostgreSQL workers skip locked expired jobs and busy queue controls when claiming
other work. Final-attempt cleanup processes at most 100 jobs per poll; skipped
jobs and larger cleanup backlogs are revisited by subsequent worker polls.

For form uploads, configure positive whole-number `requestLimits` in
`config/app.plist`; bare and quoted decimal values behave identically. Invalid
limits are rejected during configuration loading. See [Multipart Uploads](MULTIPART_UPLOADS.md)
for a complete configuration example and buffering limits.

## HTTP and data client contracts

Use `ALNSynchronousHTTPResult` for received HTTP/1.x reason phrases and opt-in
redirect-boundary responses; see [Synchronous HTTP client](HTTP_CLIENT.md).
The existing synchronous helper defaults remain unchanged. The result API uses
libcurl on GNUstep and Apple; Apple custom builds must also link `-lcurl`.

`ALNPg` date parameters preserve microseconds within the documented NSDate range;
use explicit text casts for lossless values outside it. See
[PostgreSQL timestamp precision](ARLEN_DATA.md#postgresql-timestamp-precision).
Dataverse callers can configure retry eligibility and backoff inside the client's
existing bounded loop; see [Custom retry policies](DATAVERSE.md#custom-retry-policies).

## Static asset HTTP behavior

The server automatically emits ETag and Last-Modified for static GET/HEAD,
handles conditional requests with bodyless 304 responses, preserves HEAD
representation length, and streams single byte ranges with 206 responses.
If-None-Match takes precedence over If-Modified-Since. No application middleware
or additional CLI option is needed. See [Static files](STATIC_FILES.md) for
range limits, If-Range rules, validator strength, and regression commands.

## Updating generated ORM models

After updating Arlen, regenerate existing SQL ORM model implementations with your
application's `ALNORMCodegen` generation step and rebuild. Current output safely
initializes each model descriptor on concurrent first use; older generated code
must be regenerated to receive that fix. See [ArlenORM migration notes](ARLEN_ORM_MIGRATIONS.md#generated-descriptor-initialization-update).

When automating `arlen module migrate --json`, capture stdout and stderr
separately. PostgreSQL notices may appear on stderr during repeated migrations;
parse stdout as JSON and check the exit status. Framework contributors can run
`bash tools/ci/run_postgres_regressions.sh` for isolated live database coverage;
see [Testing Workflow](TESTING_WORKFLOW.md#live-postgresql-regression-gate).
