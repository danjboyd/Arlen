# Getting Started

On Windows, `boomhauer --watch` stops its app and build-error server when the
watch process is terminated, including a forced process-tree termination.
See [Windows setup](GETTING_STARTED_WINDOWS.md) for the supported CLANG64 path.
Native watch helper header updates invalidate packaged prebuilt tools.
Automatic build-error recovery also handles same-size source edits on large
Windows checkouts.

Install Arlen, create an app, and run it locally. This page covers Linux;
use [Getting Started on macOS](GETTING_STARTED_MACOS.md) or
[Getting Started on Windows](GETTING_STARTED_WINDOWS.md) for those platforms.

## 1. Install Arlen

Paste this command into a bash or zsh terminal:

```bash
bash -o pipefail -c 'curl -fsSL https://github.com/danjboyd/Arlen/releases/latest/download/install.sh | bash -s -- --yes' && export PATH="$HOME/.local/bin:$PATH"
```

On Debian 13 (amd64/arm64) and Ubuntu 26.04 LTS (amd64), the installer can
set up missing build prerequisites and the managed clang GNUstep toolchain.
`--yes` permits setup; installing host packages may ask for your sudo password.
The framework is built once, with at most four parallel jobs. Leave off
`--yes` to be asked before prerequisite setup.

The installer verifies the release archive against `SHA256SUMS`, installs it
under `~/.local/share/arlen`, and writes a launcher to `~/.local/bin`. It
configures future bash/zsh shells automatically. The final `export` in the
command above makes `arlen` available immediately in the current shell.
The launcher loads the GNUstep environment for you.
When automatic setup needs GNUstep, it checks the bootstrap script against a
SHA256 pinned in the Arlen installer before executing it.

Check the result:

```bash
arlen doctor
```

On Windows, framework-root overrides for this bootstrap check may use native
drive-letter, UNC, or MSYS paths.

Then continue to **Create Your First App** below. No repository checkout is
needed to develop an app.

### Installation options

- `--version X.Y.Z`: select a release instead of the latest.
- `--archive FILE`: use a downloaded archive; a sibling `SHA256SUMS` is checked
  when present. Otherwise, only use a local archive you trust.
- `--no-setup`: use existing prerequisites without installing anything else.
- `--no-modify-path`: leave shell startup files unchanged; export PATH yourself.
- `--prefix DIR` and `--bin-dir DIR`: choose custom locations. Export the chosen
  bin directory in your current shell.

Rerun the installer to upgrade. A failed setup or build preserves the existing
working release. For the complete options, see [CLI Reference](CLI_REFERENCE.md).

### Manual toolchain setup

Linux releases require Arlen's pinned, patched clang/libobjc2, libdispatch and
GNUstep Base runtime. Generic clang GNUstep and GCC-built distro packages do
not satisfy the release contract. Automatic setup builds the existing custom
[gnustep-cli builder](https://github.com/danjboyd/gnustep-cli-new) natively,
using the target lock in `tools/runtime/` and the three race patches plus the Ubuntu clang compatibility patch in
`tools/ci/tsan-toolchain/` and `tools/runtime/patches/`. It supports Debian 13 amd64/arm64 and Ubuntu 26.04
amd64, using each distribution's ICU and clang. Debian 12, Ubuntu 24.04 and
Ubuntu arm64 are outside this automatic path.

Normal runtime setup restores GNUstep's `-O2` default for framework and generated
app builds through explicit tools-make/Base configure inputs. GNUstep debug
flags can still remove optimization, and existing explicit client flags keep
their precedence. An older prefix with include-only defaults must be rebuilt
at a new versioned prefix; setup never changes that older prefix in place.

The runtime is built directly at `<install-prefix>/runtimes/<target>-<lock-id>`.
GNUstep embeds that absolute path: keep it in place for every release that
uses it. The framework can move through the installer's staging/activation
steps; the runtime cannot. `ARLEN_RUNTIME_ROOT=/absolute/path` chooses another
Arlen-owned runtime root before installation. Runtime paths must have no
whitespace. Setup leaves managed GNUstep installations and system loader
configuration alone. Native compilation requires network access, disk space
for sources/builds, and several minutes; the installer asks before installing
apt prerequisites or starting it.

For manual or offline installation, provision the same patched runtime at its
final prefix first, then select it explicitly:

```bash
export ARLEN_RUNTIME_PREFIX=/absolute/final/patched-prefix
bash tools/install.sh --archive /path/to/arlen-X.Y.Z.tar.gz --no-setup
```

`--no-setup` never downloads or builds a runtime. It verifies the supplied
runtime's component pins, patch digests and ELF checksums, and requires `make`,
`python3`, clang, OpenSSL development headers and the SQLite runtime. Use
`libpq5` for PostgreSQL apps. `--no-build` only unpacks; run runtime setup or
selection before using native tools. A missing/invalid selected runtime fails
with instructions instead of falling back to a generic installation.

For a source checkout, build or select the runtime with:

```bash
python3 tools/setup_runtime.py build
# Or, for an already built matching prefix (no fetch/build):
python3 tools/setup_runtime.py select --prefix /absolute/final/patched-prefix
source tools/source_gnustep_env.sh
```

The explicit `build` command uses the existing pinned builder backend; it does
not install apt packages. See [Toolchain Matrix](TOOLCHAIN_MATRIX.md) for the
prerequisite list. The selected prefix is saved in the local, untracked
`.arlen-runtime` file. `ARLEN_RUNTIME_PREFIX` overrides that file; either
selection takes precedence over stale ambient `GNUSTEP_SH`, makefile and
`gnustep-config` settings. With no selection, contributor bootstrap retains
its existing explicit GNUstep and `/usr/GNUstep` resolution. `arlen doctor`
warns that such an unpatched contributor environment is not release-qualified;
installed releases require the patched runtime. Production `propane` and
`jobs-worker` source the same selected environment before running native
binaries. A packaged service on another host needs that host's matching final
runtime prefix in `ARLEN_RUNTIME_PREFIX` and permission to read/execute it.

### From a git checkout

Use a checkout to work on Arlen itself or to track `main`. Provision the
patched clang GNUstep runtime above first; use `./bin/arlen` in place of the installed
`arlen` command in this guide:

```bash
git clone --recursive https://github.com/danjboyd/Arlen.git
cd Arlen
source tools/source_gnustep_env.sh
./bin/arlen doctor
make all
```

This builds the main tools you will use first:

- `build/arlen`
- `build/boomhauer`
- `build/eocc`

If you want structured doctor output for automation:

```bash
arlen doctor --json
```

## 2. Create Your First App

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
arlen new MyApp
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

## 3. Run the App

From app root:

```bash
arlen boomhauer --port 3000
```

Then verify:

```bash
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/healthz
curl -i http://127.0.0.1:3000/openapi
```

When you add routes that read query or form parameters, Arlen decodes valid
percent-encoded UTF-8 once and treats `+` as a space. Malformed escapes and
encoded NUL are kept whole in core query values; see the
[App Authoring Guide](APP_AUTHORING_GUIDE.md#5-params-validation-session-and-auth-helpers).

`boomhauer` watches app files by default and rebuilds when inputs change.
Arlen reserves `/healthz`, `/readyz`, `/livez`, `/metrics`, and `/clusterz`
for built-in operability, so app routes should not reuse those paths.
`/metrics` and `/clusterz` answer `404` in production until you configure
access; see
[Configuration Reference](CONFIGURATION_REFERENCE.md#6-rate-limits-and-security-headers)
for `observability.operabilityToken` and `observability.operabilityLoopbackOnly`
(`arlen doctor --env production` warns until one is set).
The same doctor command warns in production-like environments when multiple
propane workers lack `state.durable = YES`. A database URL alone does not clear
the warning. A passing state check records your declaration; it does not verify
that each app-owned store is shared.

When using `propane` for production, repeated worker startup failures exhaust
its configured retry limit and return exit status `3`. A worker exiting during
descriptor sampling does not interrupt that policy. See [Propane](PROPANE.md).

## 4. Add One More Route

Prefer the generator-driven path for your second route:

```bash
arlen generate endpoint Hello \
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

## 5. Common Next Commands

From app root:

```bash
arlen routes
arlen config --env development --json
arlen check
```

`arlen config` prints secret values (session secrets, connection-string
passwords and similar) as `[redacted]`; pass `--show-secrets` to see them.

`arlen deploy init` writes generated secret environment examples through the
private atomic writer. The containing directory is restricted before payload
creation; permission failures stop generation instead of leaving a secret file.

Use `arlen routes` when you want to inspect registration order, route names,
and whether each route came from plist configuration or Objective-C code.

New apps ship a request test (`tests/HomeControllerTests.m`, or
`tests/HomeTests.m` in lite mode). Run it, and any tests you add, with:

```bash
arlen test --app
arlen generate test Hello --request --route /hello
```

See [Testing Workflow](TESTING_WORKFLOW.md#app-request-tests) for the
`ALNTestClient` API. `arlen test --app` also works on Windows (MSYS2
`CLANG64`); see [Windows CLANG64](WINDOWS_CLANG64.md).
On GNUstep, Arlen builds its bundled XCTest library before the app test bundle
and uses the matching headers, so no system XCTest installation is needed.

These commands also work on macOS, where they build with the Apple toolchain
instead of `make`. `arlen check` runs the Apple verification lane there, and
`arlen test` runs the Apple unit and integration bundles. `arlen perf` gates
against a baseline recorded on the same Mac.

## 6. Choose the Next Guide

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
  `examples/react_typescript_reference/README.md`. Apps without the ORM can
  generate the client and React targets from the OpenAPI export alone.
- using Dataverse through the Web API: `docs/DATAVERSE.md`

## 7. Optional Dataverse Path

If your app needs Dataverse rather than the SQL migration/schema-codegen path,
use `docs/DATAVERSE.md`. The Dataverse surface is compiled in but
runtime-inactive by default, so apps that do not configure it do not pick up
extra startup work.

## 8. Contributor Notes

If you are working on Arlen itself rather than just building an app with it:

- `make test`, `make ci-quality`, and the broader confidence lanes remain the
  deeper project-level verification path
- `docs/DEPLOYMENT.md` covers the immutable release artifact workflow; current
  release payloads package migrations plus a prepared app binary so
  `framework/bin/propane` can run directly from the built artifact, and
  `arlen deploy list|dryrun|init|push|releases|release|status|rollback|doctor|logs`
  is the preferred operator-facing wrapper, including
  `config/deploy.plist.example`, checked-in `config/deploy.plist` targets, and
  SSH-backed target deploy flows. `--json` output remains parseable when a
  successful app build emits compiler warnings on stderr. On macOS, `propane`
  continues startup-failure handling when a worker exits during an FD check
- `docs/DOCUMENTATION_POLICY.md` covers docs definition-of-done and quality
  expectations
- `docs/TESTING_WORKFLOW.md` covers the focused regression and confidence lanes

## Optional MCP tools

After ordinary routes and services work, install and explicitly enable the
[MCP module](MCP_MODULE.md) to expose selected capabilities to MCP clients.
OpenAPI inclusion does not expose tools. The [catalog example](../examples/mcp_app/README.md)
shows route and service registration with bearer authentication.
MCP 1.0.6 filters tool listings by roles, scopes, assurance, authentication
age, and route policies without running handlers. Tool calls still enforce the
full route checks.

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
and asynchronous DNS required; Debian/Ubuntu: `libcurl4-openssl-dev` or `libcurl4-gnutls-dev`). This works
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

For host-local PostgreSQL readiness, deploy doctor uses libpq in process when
a DSN is configured. Install libpq on the target host; the check fails if the
library is unavailable or the configured server is not ready.

## Background work in separate processes

`propane` passes merged configuration to its Python parser through an inherited
file descriptor, keeping configuration secrets out of the parser process arguments.

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

For vendor streams and downloads, `ALNHTTPClient` offers opt-in incremental
delivery with serial callbacks, cancellation, and separate idle/total deadlines.
Run it on an application worker; see [Outbound HTTP client](HTTP_CLIENT.md#incremental-response-delivery).

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

After upgrading the `auth` module, running `arlen module migrate` is
recommended; it enables ending a user's sessions by stamp and lets signing out
end the session on the server. The module reads each signed-in user's current roles from the
database on every request, so a role change takes effect without signing in
again; see [Auth Module](AUTH_MODULE.md#sessions-and-roles).
SMS MFA also needs the auth module's attempt-limit migration. Send and code
verification limits are stored in PostgreSQL so an old session cookie cannot
restore them; locked requests return 429 with `Retry-After`.
TOTP and SMS step-up retain the validated session generation; a concurrent
password reset or logout-all revocation makes step-up fail and clears that session.
Remove `authModule.mfa.sms.testVerificationCode` from production-like configs;
the auth module rejects this test-only bypass at startup.
Upgrade vendored `jobs` to 1.1.4 and `auth` to 1.7.5 before relying on manual
job restrictions and queued auth-mail link origins.

Auth session refresh precedes `security.routePolicies` checks, so a revoked
session cannot pass a `requireAuth` policy.
If you add session middleware in code after creating the app and before
registering the auth module, it is placed before route policies so auth can
refresh the loaded session before authorization.

If SMS is already verified, adding a TOTP authenticator requires a recent MFA
step-up. Upgrade vendored `auth` modules to 1.7.5.

Auth passwords preserve surrounding spaces on every path. If older registration
flows removed those spaces, sign in with the stored form before changing the
password. Upgrade vendored `auth` modules to 1.7.5.

Upgrade vendored `auth` modules to 1.7.6 and restart the app for the concurrent
password-reset and session-schema cache correction. Schema metadata is owned
by the auth runtime and reset when its database adapter changes; missing-table
and failed probes still retry. No additional migration is needed for this fix.

Mounted child requests are checked against the parent application's matching
`security.routePolicies` before the child receives them. A parent `requireAuth`
policy uses the parent's session configuration.

The built-in admin users search treats `%` and `_` as literal characters in
`q` and `roles` filters; see [Admin UI Module](ADMIN_UI_MODULE.md).
Admin UI CSV exports escape formula-like cells for spreadsheet use; JSON exports
keep the original values. Upgrade vendored `admin-ui` modules to 1.1.3.

Admin UI resource link fields allow relative, HTTP(S), and mailto targets;
unsafe targets render as `#` with admin-ui 1.1.3.
Upgrade vendored `search` modules to 1.2.2 before using PostgreSQL full-text
search with tenant or other resource visibility filters.
Upgrade vendored `search` modules to 1.2.3 for bounded per-query fuzzy scoring
of repeated words in the default engine. Result ranking and query limits stay
the same.
Route policies cover format-suffixed requests to a protected route, such as
`/admin.json` for `/admin`; assurance limits also apply to compiled fast routes.
Production apps keep `/openapi.json` and its docs routes closed unless they set
`openapi.publicInProduction = YES`; route metadata includes privileged API
paths. Local development keeps the OpenAPI routes enabled.
The ops module coordinates persisted dashboard history across processes when
they share its configured persistence path; see [Ops Module](OPS_MODULE.md).
New auth registrations now receive a generic accepted response and sign in
after verification. They do not get an authenticated session from the register
request. The old `authModule.registration.autoLogin = YES` flow is available
only in `development` and `test` because it reveals whether an address is
registered; see [Auth Module](AUTH_MODULE.md).
For production registration and password reset, configure a PostgreSQL jobs
adapter, apply its schema, run the jobs worker, and set
`authModule.publicBaseURL`. Auth mail is queued; the request does not wait for
the mail provider. See [Durable Jobs](DURABLE_JOBS.md) and
[Auth Module](AUTH_MODULE.md).

When automating `arlen module migrate --json`, capture stdout and stderr
separately. PostgreSQL notices may appear on stderr during repeated migrations;
parse stdout as JSON and check the exit status. Framework contributors can run
`bash tools/ci/run_postgres_regressions.sh` for isolated live database coverage;
see [Testing Workflow](TESTING_WORKFLOW.md#live-postgresql-regression-gate).

If you install `storage`, set `ARLEN_STORAGE_SIGNING_SECRET` (32+ characters)
before running outside `development` or `test`; the module refuses to start
without it. See [Storage Module](STORAGE_MODULE.md#signing-secret).

Generate signing secrets (`ARLEN_SESSION_SECRET`, `ARLEN_AUTH_BEARER_SECRET`,
`ARLEN_STORAGE_SIGNING_SECRET`) with `openssl rand -hex 32`. Outside
`development` and `test`, startup refuses placeholder values and secrets copied
from the Arlen examples; see
[Signing secrets](CONFIGURATION_REFERENCE.md#signing-secrets).

When you move your Arlen framework pin, re-run `arlen module upgrade <name>
--source <framework>/modules/<name>` for each vendored module, then
`arlen module doctor`. Module sources can change without a version bump; see
[Upgrade a Module](MODULES.md#6-upgrade-a-module). An upgrade keeps a module you
disabled disabled.

To push notifications to phones and browsers, enable the notifications module's
Web Push channel: `arlen webpush generate-keys` prints a VAPID key pair for the
server environment. See [Notifications Module: Web Push](NOTIFICATIONS_MODULE.md#web-push).
Notification workers sharing a persistence path coordinate writes across
processes and refresh inbox, outbox, and preference reads from shared state.
For signed-in users queueing their own notification, the module replaces the
email recipient and removes address-bearing mail headers such as `Reply-To` and
`Resent-*`; upgrade vendored notification copies to 1.3.1 for this behavior.
Jobs workers sharing a persistence path also refresh reads and transact operator-state changes;
job claim durability still depends on the configured jobs adapter.
Search workers refresh shared state and reject conflicting rebuild/update results
instead of overwriting newer state. External engines still require one reindex
worker per resource unless the backend fences publication; see [Search Module](SEARCH_MODULE.md).
Search query filters also constrain promoted results, so a promoted record that
does not match `filter.<field>` or a per-resource filter is omitted.

`arlen module add ops` works without jobs, notifications, storage, or search.
With ops 1.1.1, operator views show queue, notification, and storage status
without individual job, outbox, or storage records; admins retain detail.
Missing module summaries are marked unavailable. See [Ops Module](OPS_MODULE.md)
for authentication requirements when composing a partial module installation.
Notifications 1.3.2 removes webhook URLs and headers from persisted outbox
records; upgrade vendored modules and rotate older exports or backups that held
webhook credentials.

Session cookies use `Path=/` across a mounted app tree. Use distinct
`session.cookieName` values for any enabled sessions with different secrets,
including siblings or descendants behind a session-disabled app. Startup
rejects a shared name with different secrets. A shared name and secret, as used
by the admin UI child app, remains supported.

For company sign-in, add `auth`, configure an OIDC provider and an application
identity resolver, and explicitly disable stub/password access if your copied
manifest enables it. Follow the [Entra example and upgrade steps](AUTH_MODULE.md#configurable-oidc-login-including-microsoft-entra).

Security-header defaults are shared safely across concurrent first requests.
Explicit response headers and configured CSP remain supported; see
[Response Headers](RESPONSE_HEADERS.md#concurrent-security-headers).

On GNUstep, avoid `@synchronized` on instances that several request threads
share; create an `NSLock` in the initializer instead. See
[Toolchain Matrix](TOOLCHAIN_MATRIX.md#known-libobjc2-defect-instance-synchronized).

Create process-wide lazy objects, such as a shared `NSRegularExpression`, with
`dispatch_once` rather than `if (x == nil) { x = ...; }`. Concurrent first
requests can otherwise race, and one thread can free the object another is
using.

Normal HTTP responses have a five-minute total send deadline and require an
average of 1 KiB/s after a ten-second grace period. This prevents slow readers
from occupying every HTTP worker. For unusually slow bulk downloads, adjust
`requestLimits.responseSendTimeoutSeconds`, `responseMinBytesPerSecond`, and
`responseMinRateGraceSeconds` in your app configuration. SSE and WebSocket
sessions use separate policies. See [Configuration reference](CONFIGURATION_REFERENCE.md).

For PostgreSQL queries whose values vary per request, use bound builder
parameters. The connection cache reuses their SQL shape while keeping each
call's parameter values separate. See [Arlen Data](ARLEN_DATA.md).

The built-in `rateLimit` budget is **per worker**. With four propane workers,
a client can receive up to four times `rateLimit.requests` in one window by
opening connections across workers. Startup logs `rate limit is per worker`
when rate limiting and multiple workers are configured. Use an ingress rate
limiter for a deployment-wide quota; authentication's account attempt limits
are separate from this request middleware.

Use PostgreSQL's `enumerateQuery:parameters:batchSize:usingBlock:error:` for
large exports instead of collecting all rows with `executeQuery:`. Process
rows as they arrive and avoid retaining them to keep client memory bounded.

Request metrics batch completed-response counters and timings under one lock
and box their numeric values only when taking a snapshot. The metrics names
and snapshot/Prometheus formats remain compatible. PostgreSQL ORM reads without
raw expressions avoid a session-reset round trip; raw expressions and
transactions retain conservative cleanup.

Filesystem-backed storage downloads stream the verified open file, support HEAD
and byte ranges, and use checksum ETags. Variant source data defaults to a 16 MiB
limit (`storageModule.maxVariantInputBytes`). See [Storage Module](STORAGE_MODULE.md)
for custom-adapter behavior and file immutability requirements.

Storage and notifications persistence now use transactional SQLite catalogs. Linux hosts
need `libsqlite3-0`; macOS and supported Windows use the system SQLite runtime.
CI provisioning validates that runtime. Stop old workers before the one-time
legacy import; see [Storage Module](STORAGE_MODULE.md) and
[Notifications Module](NOTIFICATIONS_MODULE.md#incremental-persistence-and-upgrading)
for migration and backup rules.
Storage 1.4.2 refuses cached object reads and downloads after a catalog reload
fails; repairing the catalog permits a later successful reload. Backend
exceptions release writer locks and force a reload of persisted state. Upgrade
vendored storage modules with `arlen module upgrade`.

Normal-response allocation-error fallbacks use the configured response send
budget and close the connection after the fallback 500 response.

Default security headers are validated once when the application is configured
and applied without replacing response-specific values. Public header setters
continue to reject invalid names and CR/LF/NUL injection. For local performance
investigation, `make response-header-perf-bench` builds an optional focused
benchmark; see [Performance Profiles](internal/PERFORMANCE_PROFILES.md).

Auth-only apps can build without the optional jobs module. Durable auth mail
still requires jobs and its durable adapter; see [Auth Module](AUTH_MODULE.md).

For Linux contributor sanitizer checks, run `make ci-sanitizers` after sourcing
`tools/source_gnustep_env.sh`. The gate requires clang's shared sanitizer runtime
and uses it consistently for XCTest bundles and instrumented child processes.

## Upgrading existing applications

Re-vendor the first-party modules you use with
`arlen module upgrade <name> --source <framework>/modules/<name>`, then rebuild
and redeploy. Upgrading framework binaries alone does not replace copied
module sources. JSON input is limited to 512 nested containers on both parser
backends. See [Live UI](LIVE_UI.md) for receive-only channels and reconnect
behavior. Custom Windows CLANG64 build scripts must include
`_FILE_OFFSET_BITS=64` and rebuild application objects after upgrading; standard
CLI and make paths set it automatically.

Redis cache configuration: `ALNRedisCacheAdapter` rejects literal NUL and `%00`
in Redis URLs before parsing. If adapter initialization reports this error,
correct `ARLEN_REDIS_URL` (or the URL passed by your application); no connection
is made using a truncated destination. Ordinary percent-encoded credentials
remain supported.

## Request limits with multiple workers

The built-in request rate limiter requires one worker. Startup rejects
`rateLimit.enabled = YES` when multiple workers are configured (the propane
default is four). Select `propane --workers 1` or the propane accessory
`workerCount = 1`, or disable the built-in limiter and enforce the budget at
ingress. v0.3.0 only warned about multiplied budgets; startup now fails closed.
See [propane's state contract](PROPANE.md#multi-worker-state-contract).

An unfilled EOC `content` yield escapes its context fallback; `ALNView` still
renders the captured page body as HTML in a filled content slot.

`renderNegotiatedTemplate:context:jsonObject:error:` uses only `jsonObject` for
JSON responses; nil produces `{}`. Responses include `Vary: Accept` so caches
separate HTML and JSON variants.
Template rendering restores thread-local options and composition slots when a
body or layout throws. Exceptions still propagate to the caller; failed renders
do not leave slot content available to later renders on the same worker thread.
Nested rendering preserves the enclosing render state.

ORM transaction exceptions now restore context connection state. Throwing
savepoint blocks roll back their writes before an enclosing transaction can
continue; PostgreSQL and MSSQL connections close if that cleanup fails. See
[Arlen ORM](ARLEN_ORM.md) for the adapter contract.

Live keyed broadcasts require explicit server-selected container and key values.
Publish helpers omit requester-specific metadata and tracing IDs; direct live
responses retain request defaults. See [Live UI](LIVE_UI.md).

PostgreSQL and MSSQL decimal result decoding rejects text longer than 40
characters or containing more than 38 digits with a query error. This also
applies to PostgreSQL numeric arrays. Select wider values as text when exact
arbitrary precision is required; see `docs/GETTING_STARTED_DATA_LAYER.md`.

Synchronous HTTP compatibility helpers reject invalid header names and values
before transport, including CR/LF injection and embedded NUL. They return
`NSURLErrorDomain/NSURLErrorBadURL`; see [HTTP Client](HTTP_CLIENT.md).

With llhttp enabled, chunked uploads enforce the selected route's decoded body
limit and spool above `spoolThresholdBytes` while receiving. Chunk framing is
processed incrementally within the existing encoded envelope cap. The legacy
backend continues to reject chunked transfer coding. See
[Configuration Reference](CONFIGURATION_REFERENCE.md).

Legacy storage plist catalogs use private temporary creation and atomic replacement
on Windows; the parent directory ACL is unchanged. See
[Storage Module](STORAGE_MODULE.md) for upgrade and filesystem guidance.

Request body deadlines and minimum rates also apply to the final body fragment,
including uploads spooled to disk. A late completion receives `408` and its
incomplete spool is removed. Each keep-alive request starts its own body clock.

Windows uses a bounded graceful close after HTTP parser rejection or session/worker
queue admission rejection to preserve the error response when input is queued. See
[Configuration Reference](CONFIGURATION_REFERENCE.md).

Native runtime qualification also runs the fixed-date contract in
`tests/fixtures/runtime/icu_runtime_contract.m`. It verifies Chicago winter and
summer offsets through `NSTimeZone`, exact POSIX-locale date formatting through
`NSDateFormatter`, and records the actual ICU library/data/timezone versions.
Install `tzdata` for system zoneinfo; each target keeps its distribution's ICU
without an external timezone-data override. Native-control and ICU failure logs
are retained by the installer smoke's artifact cleanup path.

HTTP signal shutdown uses a lock-free atomic stop flag shared with workers,
including Windows console-control shutdown. Supported clang builds enforce
lock-free access at compile time; shutdown commands and limits are unchanged.
