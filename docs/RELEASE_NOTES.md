# Release Notes

## Unreleased

- `propane` and `jobs-worker` run on macOS. They build with the Apple
  toolchain instead of `make` and run the app from
  `.boomhauer/apple/boomhauer-app`, and `propane`'s FD-pressure checks use
  `lsof` where `/proc` is missing. `propane`, `jobs-worker` and `arlen doctor`
  no longer use bash 4 syntax that macOS `/bin/bash` 3.2 rejects: `${var,,}`,
  a heredoc inside `< <(...)`, and expanding empty arrays under `set -u`.
  Before, `propane` aborted at startup on macOS. `ShellPortabilityTests` guards the scripts that run on
  macOS against those constructs (GitHub issue 144).

- Boolean `NSNumber`s are now detected the same way everywhere, using the new
  `ALNNumberIsBoolean()` in `ALNPlatform.h`, and correctly on Apple arm64. The
  old checks compared `objCType` with `@encode(BOOL)`, which is `"B"` on Apple
  arm64 while `@YES` reports `"c"`. On macOS the MCP module therefore rejected
  its tools' boolean annotations and boolean schema values, and the OAuth
  resource server accepted JSON `true` as a numeric claim. PostgreSQL, MSSQL and
  Dataverse also bound `@YES` as `1`, and ORM codegen emitted booleans as
  numbers. On GNUstep, `numberWithChar:` values are no longer treated as
  booleans. `auth` moves to `1.5.1` and `mcp` to `1.0.3` (GitHub issue 132).

- Markdown support: `ALNMarkdown` parses CommonMark and GitHub Flavored
  Markdown with a vendored cmark-gfm `0.29.0.gfm.13` into an Objective-C node
  tree for custom renderers. It also has an HTML renderer that is safe for
  untrusted input (raw HTML is escaped, link URLs are limited to `http`, `https`
  and `mailto`, and a class map can style the output), and a plain-text
  renderer. Tables, task lists, strikethrough and autolinks can be switched per
  call, apps can register custom inline spans such as `⟦red⟧text⟦/red⟧` that
  arrive as typed nodes, and templates can use `<%== ALNEOCMarkdownHTML($body) %>`.
  See `docs/MARKDOWN.md` (GitHub issue 127).

- The vendored test runner is now `danjboyd/tools-xctest` `v0.5.0` (was
  `v0.3.0`). A `TEST=` filter or `arlen test --only` selection that matches
  no test now fails the run with `No tests matched '<selection>'.` instead of
  passing with nothing run, and so does a run in which no test executes.
  Class-level `+tearDown` now runs even when `+setUp` failed or skipped the
  class. The fork also builds on Windows (MSYS2 `CLANG64`) now, which removes
  its side of the blocker on moving the Windows lanes to it (GitHub issue 116).

- Tests wait for real signals instead of sleeping for guessed intervals.
  `tests/shared/ALNTestWait.h` adds `ALNTestWaitUntil`,
  `ALNTestWaitForTaskExit`, and `ALNTestWaitForTCPPort`, built on
  `XCTestExpectation`/`XCTWaiter`; 26 sleep-and-poll waits in the unit,
  integration, browser-audit, and durable-jobs suites now use them. The
  docs gate runs `tools/ci/check_test_sleeps.py`, which rejects new sleeps in
  `tests/` unless marked `// sleep-ok: <reason>` (GitHub issue 114).

- Fixed the intermittent `testBlobEndpointSendfileModeMatchesBinaryPayload`
  failure. The HTTP integration helpers passed request URLs to the shell
  unquoted, so the `&` in `?size=8192&mode=sendfile` sent curl to the
  background and the test read whatever it had written so far.

- CI now notices tests that silently stop being discovered. `make
  test-inventory` compares what the unit and integration bundles discover
  (`xctest -list-tests`) with the committed lists in
  `tests/fixtures/test_inventory/`, and `linux-quality` fails on any
  difference. After adding, removing, or renaming tests, run
  `make update-test-inventory` and commit the result (GitHub issue 115).

- XCTest make targets accept `ITERATIONS=<n>` and `UNTIL_FAILURE=1` to repeat
  tests when hunting flakes, and the TSAN lane can repeat its unit run with
  `ARLEN_TSAN_UNIT_ITERATIONS` (GitHub issue 113). Failed tests are never
  retried; a new `linux-quality` check keeps `-retry-tests-on-failure` out of
  the build and CI wiring.

## 0.1.0 — 2026-10-07

First tagged release. [Status](STATUS.md) describes everything this release
ships; the entries below are the changes made since release candidates started
being tracked here.

- The OpenAPI docs UI (`/openapi`, `/openapi/viewer`, `/openapi/swagger`)
  works under the default `default-src 'self'` Content-Security-Policy. Its
  pages previously used inline style and script, which the default policy
  blocked, leaving the explorer unstyled with an empty operation list. The CSS
  and JS are now served from `/openapi/assets/*` (GitHub issue 121). The
  development exception page likewise loads its stylesheet from
  `/arlen/dev-error.css` instead of an inline `<style>` block.

- Arlen is now licensed under LGPL-2.1-or-later. The previous grant (LGPL-2.0,
  version 2 or any later version) already allowed this; `LICENSE` now carries
  the unmodified LGPL-2.1 text so license scanners detect it.

- The MCP module no longer crashes the app at startup when it is loaded but
  `mcp.enabled` is NO; a module that did not install is inert. The `mcp` module
  moves to `1.0.2` (GitHub issue 105).

- `arlen module upgrade` keeps the app's settings in the module lock entry
  instead of resetting `enabled` to YES, and stamps the copied files with the
  install time so incremental builds no longer link stale module objects
  (GitHub issue 106). See [CLI reference](CLI_REFERENCE.md).

- `ALNOAuthResourceServer` accepts old-style plist string forms in its
  configuration: digits for `jwksMaxAgeSeconds` and `refreshCooldownSeconds`,
  and `YES`/`NO` or `true`/`false` for `refreshOnRequest`, `preflightOnStart`
  and `allowApplicationPermissions`. This covers an `mcp.oauth` block in
  `app.plist` (GitHub issue 107).

- `ALNHTTPClient`, an outbound HTTP client for calling third-party APIs from app
  code. Every request and redirect hop must go to a host on an allowlist fixed
  at construction; each request has one total deadline and a response size
  limit; redirects are off by default and never followed for a request carrying
  `Authorization` or `Cookie`; errors and optional log lines never contain
  headers, bodies or query strings. `GETURL:`, `POSTJSONObject:` and
  `performRequest:` return the existing `ALNHTTPClientResult` (GitHub issue 99,
  HelpDesk ARLEN-FR-011). See [HTTP client](HTTP_CLIENT.md).

- `ALNOAuthResourceServer` logs why it rejected a bearer token: one WARN line
  per request (`event=token.rejected`) with a `reason` naming the failed check,
  `signature_verified`, and `client_id` once the signature verified. The token
  and other claim values are never logged. The catch-all "Invalid access token
  claims" and "Invalid Entra access token profile" errors are split into
  specific reasons, including an Entra app-only token missing the optional
  `idtyp` claim (GitHub issue 96). See
  [OAuth resource servers](OAUTH_RESOURCE_SERVER.md#verification-and-operations).

- OIDC providers accept an `assurance` map from verified ID-token `amr` and
  `acr` values to an assurance level, for example `amr = { mfa = 2; }`, so an
  MFA sign-in at the identity provider reaches module surfaces that need level
  2 without a hand-written resolver rule. Unmatched or absent claims give 1. A
  resolver that returns `assuranceLevel` still wins, and sees the mapped level as
  `assurance_level`. The auth module moves to `1.5.0` (GitHub issue 98). See
  [Auth Module](AUTH_MODULE.md#provider-assurance-from-amr-and-acr).

- Configurable step-up target for module surfaces: `authModule.paths.stepUp`
  (default: the TOTP page) is where the admin UI, jobs, notifications, ops,
  search and storage modules send a user who needs assurance level 2. Apps whose
  users sign in only through an identity provider can point it at the provider
  login, for example `/auth/provider/entra/login?prompt=login`, instead of a
  TOTP page those users have no factor for. Provider login routes now accept
  `prompt=login`. The auth module moves to `1.4.0`; the six modules take patch
  versions and fall back to the TOTP path with an older auth module (GitHub
  issue 97). See [Auth Module](AUTH_MODULE.md#step-up-for-provider-sign-in).

- HTTP status lines carry the right reason phrase for more codes: `401` (which
  previously went out as `401 OK`) and 17 others, including `202`, `303`, `307`,
  `308`, `409`, `410`, `415`, `501`, `502` and `504`. A status Arlen does not know
  now gets an empty reason phrase, as RFC 9112 allows, instead of `OK`. Phrases
  that were already correct are unchanged.

- Security: the auth module no longer redirects off-origin after sign-in.
  `return_to` from the query string or a form field reached the post-login
  `Location` header unvalidated, so a link such as
  `/auth/login?return_to=https://evil.example/` sent a user who genuinely
  signed in to another site. Every `return_to` read and the
  `postLoginRedirectForContext:` sink now keep only a single-slash absolute
  path and otherwise fall back to `defaultRedirect`. Behaviour change: apps
  that relied on cross-origin `return_to` must return that URL from the
  session policy hook's
  `authModulePostLoginRedirectForContext:user:defaultRedirect:`, which is not
  clamped. See [Auth Module](AUTH_MODULE.md#customization-hooks).

- Live push and durable event streams across propane workers and hosts:
  `realtime.fanout = { adapter = "postgresql"; }` gives `ALNRealtimeHub` a
  PostgreSQL `LISTEN`/`NOTIFY` fanout, so `publishLive…onChannel:` reaches
  websocket subscribers on every worker, not only the one that handled the
  publishing request. `eventStreams.store` and `eventStreams.broker` with
  `adapter = "postgresql"` add `ALNPgEventStreamStore` (per-stream advisory
  locks, idempotency and replay identical to the in-memory store) and
  `ALNPgEventStreamBroker`, so replay and `resync_required` hold across workers.
  Live delivery is at most once; durable streams recover through replay. Without
  a fanout, a worker running under several propane workers warns once when a
  websocket channel opens. New public pieces: `ALNRealtimeFanout`,
  `ALNPgRealtimeFanout`, `ALNPgConnection waitForNotificationsWithTimeout:error:`,
  and `ALNEventEnvelope envelopeWithDictionary:` (GitHub issue 48). See
  [Live UI](LIVE_UI.md#multiple-workers-and-hosts) and
  [Durable Event Streams](EVENT_STREAMS.md#postgresql-store-and-broker).

- `/readyz` fails (`503`) while the running release has schema migrations that
  are not applied, by default in `production`
  (`observability.readinessRequiresMigrations`,
  `ARLEN_READINESS_REQUIRES_MIGRATIONS`). The JSON payload's
  `checks.schema_migrations` lists the pending versions. The check is read-only,
  rechecks while not ready so `arlen migrate` restores readiness without a
  restart, and `arlen deploy status` reports `not ready (N migrations pending)`
  (GitHub issue 90). See [Deployment](DEPLOYMENT.md).

- Deploy releases record their source revision: the app and framework git
  commits plus dirty flags, in `manifest.json` (`source_revision`) and
  `release.env` (`ARLEN_RELEASE_APP_GIT_SHA`, `ARLEN_RELEASE_APP_GIT_DIRTY`,
  `ARLEN_RELEASE_FRAMEWORK_GIT_SHA`, `ARLEN_RELEASE_FRAMEWORK_GIT_DIRTY`). App
  dirtiness covers only what the release packages, so untracked build output
  does not count. `deploy status` and `deploy releases` show the short SHA with
  `+dirty`, and `deploy push --require-clean` refuses a dirty app (GitHub
  issue 89). See [Deployment](DEPLOYMENT.md).

- Deploy targets accept `sharedPaths` (app-relative paths such as uploads that
  `deploy init` creates under `shared/` and every release links to, so their
  files survive the next release) and `prePackageCommands` (for example
  `npm --prefix frontend run build`, run from the app root before packaging; a
  failure aborts the build and reports the command's output). `deploy doctor`
  checks that shared paths exist and are writable. `deploy push --json` now
  carries the build script's own error message (GitHub issue 66). See
  [Deployment](DEPLOYMENT.md).

- App request tests: `ALNTestClient` builds an app from its config with its own
  routes and dispatches requests in process, with a cookie jar, automatic CSRF,
  session access and `signInAsSubject:`. `arlen test --app` builds and runs an
  app's `tests/**/*.m`, `arlen generate test <Name> --request` scaffolds a
  request test, and new full and lite apps ship a passing one. App code needs no
  changes: the test build captures route registration from the app's `main`
  (GitHub issue 65). See [Testing Workflow](TESTING_WORKFLOW.md#app-request-tests).

- CSRF no longer starts a session on every request without a session cookie.
  The middleware used to write a fresh token into the session up front, so every
  cookieless request, `GET` and `HEAD` included, got a new signed-out session
  cookie. When a browser sent such a request while signed in (for example a
  service worker's fetch), the reply replaced the real session and signed the
  user out. The token is now created when a request first reads it, and only
  then is `Set-Cookie` sent (GitHub issue 86). See
  [Configuration Reference](CONFIGURATION_REFERENCE.md#5-session-and-csrf).

- MCP module: `maxOutputBytes` and `requestsPerMinute` written as bare numbers
  in `config/app.plist` (as in the documented example) no longer crash startup
  (`does not recognize unsignedIntegerValue`). Plist strings holding
  decimal integers are accepted, and other values fail startup with an error
  naming the key. Tool definitions' `minimumAuthAssuranceLevel` and
  `maximumAuthenticationAgeSeconds` get the same checks. The module version is
  now `1.0.1` (GitHub issue 42). See [MCP Module](MCP_MODULE.md).

- Auth module `module-ui`: `auth.css` and `auth_totp_qr.js` are now also
  served under the module's own prefix at `<paths.prefix>/assets/`, and pages
  link them there, so sign-in pages keep their styling behind a reverse proxy
  that only forwards `paths.prefix`. `/modules/auth/` still serves them. The
  auth module version is now `1.2.0` (GitHub issue 51). See
  [Auth Module](AUTH_MODULE.md).

- CSRF: `csrf.exemptPathPrefixes` lets a mixed browser app serve bearer
  clients, such as the MCP endpoint, on chosen paths without a CSRF token.
  The exemption applies only to requests that carry no session cookie. Requests
  with the session cookie still need a token, and exempt requests do not mint a
  session. Invalid entries fail startup (error `339`) (GitHub issue 43). See
  [Configuration Reference](CONFIGURATION_REFERENCE.md#5-session-and-csrf) and
  [MCP Module](MCP_MODULE.md).

- Per-route body limits: `route.maxBodyBytes` (or `maxBodyBytes` on a plist
  route) overrides `requestLimits.maxBodyBytes` for that route. The server
  resolves the route from the request line and answers `413` before reading any
  of an oversized body, so an app can keep a small global limit and allow large
  uploads on a few routes. Multipart parsing on such a route uses the route
  limit. Measured with 8 concurrent 20 MiB uploads, anonymous memory grew about
  4 MiB, because bodies and parts live in spool files. Chunked request bodies
  remain unsupported (`400`) (GitHub issue 87). See
  [Configuration Reference](CONFIGURATION_REFERENCE.md#3-request-limits).

- Large uploads: request bodies larger than `requestLimits.spoolThresholdBytes`
  (default 1 MiB) stream from the socket into a private temporary file under
  `requestLimits.spoolDirectory`, and `request.body` maps it, on both parser
  backends. Multipart file parts above the same threshold are written to their
  own temporary files instead of being copied into `NSData`: `ALNUpload`
  exposes `temporaryFilePath`, `data` maps the file, and `writeToFile:error:`
  moves it. Spool files are removed when the request ends, including on
  exceptions and client disconnects. With the default limits nothing is
  spooled (GitHub issue 64). See [Multipart Uploads](MULTIPART_UPLOADS.md).

- `headerValueForName:` on `ALNController` and `ALNContext` is now declared
  nonnull, matching what it returns: an absent header gives `@""`, as
  `ALNRequest` already documented. The empty-name case, which returned `nil`,
  now also returns `@""`. Code that checked `== nil` or relied on `?:` to fall
  back never saw a missing header; test `length == 0` instead. The storage
  module's upload endpoint had such a fallback to a `?token=` query parameter
  that could never trigger; it was removed, and tokens remain header-only
  (GitHub issue 80).

- Modules: relative jobs, storage, notifications and search persistence paths,
  including the `var/module_state/...` defaults, now resolve against the
  application root instead of the process working directory.
  `arlen jobs worker` runs from the framework root, so it had been reading and
  writing scheduler state under the framework checkout, separately from the
  server. Adds `-[ALNApplication appRootPath]` and `-pathRelativeToAppRoot:`
  (GitHub issue 76).

- Deploy: `deploy push` and `deploy release` for SSH targets no longer look for
  the host's release layout on the operator's machine. They check it on the
  host over SSH and report the missing host paths (`deploy_target_not_initialized`),
  or fail with `deploy_target_transport_failed` when SSH is unreachable.
  Missing local generated artifacts are regenerated automatically. The new
  `arlen deploy init <target> --remote` creates the layout on the host over
  SSH. There is no longer any need to mirror the host path locally (GitHub
  issue 69).

- Deploy: remote `arlen deploy release|status|doctor|logs|rollback` on SSH
  targets now sources `runtime.gnustepScript` before running the packaged
  `arlen` when `runtime.requiresEnvWrapper` is on. Before this, hosts whose
  GNUstep libraries are not on the loader path failed with
  `libgnustep-base.so: cannot open shared object file`. A configured script
  that is missing on the host fails clearly with `missing GNUstep.sh: <path>`
  (GitHub issue 71).

- Routing: `HEAD` requests now fall back to the matching `GET` route when no
  `HEAD` or `ANY` route matches (RFC 9110 section 9.3.2). They return the same
  status and headers, including `Content-Length`, without a body. Before this,
  `curl -I`, uptime checks and link unfurlers got a 404 for any `GET`-only
  route. Explicit `HEAD` routes still take precedence (GitHub issue 68).

- Security: static-mount responses, route-miss 404s and built-in endpoints
  (OpenAPI docs pages, `/healthz`, `/arlen/live.js`) did not carry the
  configured security headers, because they are produced outside the
  middleware chain. HTML served from a static mount had no CSP or
  `X-Frame-Options`, and static assets had no `nosniff`. These responses now
  get the same headers as routed responses, without overriding headers
  already set. `securityHeaders.enabled = NO` still disables them everywhere
  (GitHub issue 81). See
  [Response Headers](RESPONSE_HEADERS.md#concurrent-security-headers).

- Single-page apps: a new top-level `spaFallback` serves the app shell for deep
  links. It applies only when no route or built-in matched, the request is an
  HTML navigation (a `GET`/`HEAD` whose `Accept` contains `text/html`), and the
  path is outside `excludePrefixes` and has no file extension. The shell goes
  through the app's middleware (security headers, session/CSRF) and is served
  with `no-cache` and ETag/304. Apps can drop hand-written catch-all routes,
  which also stopped the OpenAPI and `/arlen/live.js` built-ins from being
  reached (GitHub issue 62). See
  [Static files](STATIC_FILES.md#spa-history-fallback).

- Static mounts accept `cacheControl`, either one value or glob patterns with a
  `default` (for example immutable caching for hashed `assets/*` and `no-cache`
  for `index.html`). The default `/static` mount reads the top-level
  `staticCacheControl` or `ARLEN_STATIC_CACHE_CONTROL`. Static responses
  previously sent no `Cache-Control` at all (GitHub issue 62, Cache-Control
  part). See [Static files](STATIC_FILES.md#cache-control).

- Auth module OIDC: `authModule.failureRedirect`, or a provider's own
  `failureRedirect`, sends failed browser callbacks to a local page with
  `?error=<code>&provider=<identifier>` instead of a raw 401 JSON body. The
  stable codes are `rejected`, `admission_denied`, `expired_state`,
  `provider_error`, `verification_failed` and `provider_unavailable`, and a
  resolver can supply its own through `ALNAuthModuleOIDCFailureCodeKey`. The
  JSON API callback keeps its 401 and now includes `code`. External redirect
  targets fail at startup (GitHub issue 75). See
  [Auth Module](AUTH_MODULE.md#failure-redirect).

- Auth module OIDC: `preset = "google"` expands into Google's issuer, discovery
  URL, scopes and client authentication method. The endpoint and JWKS allowed
  hosts are now derived from the preset's endpoints, so they no longer have to
  be listed by hand. Explicit keys override the preset, and unknown or
  unsupported presets fail at startup (GitHub issue 60). See
  [Auth Module](AUTH_MODULE.md#google-preset).
- Auth module OIDC: an optional per-provider `admission` policy restricts
  sign-in to verified allowlisted emails, domains (honoring Google's `hd`
  claim), or an environment-supplied email list. It runs before the resolver
  and never links identities (GitHub issue 61). See
  [Auth Module](AUTH_MODULE.md#admission-policy).

- CSRF: rejected requests from JSON clients (JSON `Accept`, `/api` paths, or
  `apiOnly`) now receive the structured error envelope with code `csrf_invalid`
  instead of a plain-text body. Other clients still get the plain-text 403.
  Tokens are now compared in constant time (GitHub issue 63). See
  [Configuration Reference](CONFIGURATION_REFERENCE.md#5-session-and-csrf).
- Security hardening: `ALNConstantTimeDataEquals` and the session middleware's
  signature check truncated the length difference to one byte. Inputs whose
  lengths differed by a multiple of 256, with zero-byte padding, could therefore
  compare equal. Lengths are now compared at full width.
- Auth module OIDC: in `development` and `test`, `redirectURI` may be a loopback
  http URL (`localhost`, `127.0.0.1`, `[::1]`), so real Google or Entra login
  works against `boomhauer`. Other environments still require HTTPS, and
  provider endpoints are always HTTPS-only (GitHub issue 59). See
  [Auth Module](AUTH_MODULE.md).
- Static files: `Content-Type` now comes from a public `ALNMIMETypes` table.
  gif, ico, webp, woff, woff2, map and xml were allowed by default but served as
  `application/octet-stream`; they now get specific types, as do common audio,
  video, image and document types. Apps can add or override entries with a
  top-level `mimeTypes` dictionary (GitHub issue 57). See
  [Static files](STATIC_FILES.md#content-types).
- Controllers can serve private files with
  `renderFileAtPath:contentType:options:`, and other code with
  `+[ALNFileResponse prepareResponse:...]`. These use the same ETag/Last-Modified,
  conditional GET, single byte range (206/416), HEAD and sendfile behavior as
  static mounts. Options set `Cache-Control`, a download filename and a
  caller-supplied ETag. This fixes Safari/iOS media playback for authenticated
  audio and video (GitHub issue 58). See
  [Static files](STATIC_FILES.md#controller-file-responses).
- `ALNPg` and `ALNMSSQL` accept an optional `acquireTimeout`: when every pooled
  connection is in use, `acquireConnection:` waits up to that many seconds for
  one to be released before failing with the pool-exhausted error. The default,
  `0`, keeps the existing fail-fast behaviour. Pool connects, checkout liveness
  checks and release-time rollbacks no longer run under the pool lock, and
  `poolDiagnostics` reports occupancy, wait and exhaustion counters. The
  optional `database.poolAcquireTimeoutSeconds` config key
  (`ARLEN_DB_POOL_ACQUIRE_TIMEOUT_SECONDS`) is normalized for apps to pass
  through. See
  [ArlenData](ARLEN_DATA.md#connection-pool-acquire-timeout).
- Security: the `storage` module no longer signs upload and download tokens
  with a built-in default key when `storageModule.signingSecret` is unset
  (GHSA-cmxm-f294-r8qh). Set `ARLEN_STORAGE_SIGNING_SECRET` (new) or
  `storageModule.signingSecret`, at least 32 characters. Outside
  `development`/`test` the module now refuses to configure without one; in
  `development`/`test` it uses a random per-process key and logs a warning.
  Tokens issued under the old default key stop validating. See
  [Storage Module](STORAGE_MODULE.md#signing-secret).
- Framework objects no longer use `@synchronized` on instances, working around
  a GNUstep libobjc2 first-use lock race
  ([gnustep/libobjc2#424](https://github.com/gnustep/libobjc2/issues/424)).
  Concurrent first requests could hang, abort in `objc_sync_enter`, or corrupt
  the PostgreSQL pool. Metrics, database pools, routing, rate limiting, OAuth
  key caching and template registries now use locks created before the object
  is shared. See the
  [Toolchain Matrix](TOOLCHAIN_MATRIX.md#known-libobjc2-defect-instance-synchronized).
- PostgreSQL date parameters retain six fractional digits for scalar and array
  round trips. The documented precision range and lossless text alternative are
  in [ArlenData](ARLEN_DATA.md#postgresql-timestamp-precision).
- Dataverse clients expose a retry-delay policy and injectable sleeper, preserving
  the existing defaults and hard attempt bound.
- The additive synchronous HTTP result API returns complete redirect-boundary
  responses on request and exposes received HTTP/1.x phrases on GNUstep and Apple.
  Apple builds now link system libcurl for this API. Existing helpers retain
  their defaults and platform transports.

- Multipart limits accept bare or quoted decimal plist values without crashing
  the server. Invalid request limits now fail configuration loading with a keyed
  error; direct parser calls return an error instead of raising an exception.
- PostgreSQL job claims skip locked expired jobs and busy queue controls.
  Terminal cleanup is bounded to 100 jobs per poll, so unrelated work can proceed.

Certification evidence:

- Certification pack: `build/release_confidence/phase9j/manifest.json`
- JSON performance pack: `build/release_confidence/phase10e/manifest.json`
- Release certification workflow: `make ci-release-certification`
- JSON performance workflow: `make ci-json-perf`
- Known risk register: [Known Risk Register](KNOWN_RISK_REGISTER.md)

## Notes

- Release candidates are incomplete unless the certification manifest status is `certified`.
- Release candidates are incomplete unless the JSON performance manifest status is `pass`.
- `tools/deploy/build_release.sh` enforces both requirements by default.
