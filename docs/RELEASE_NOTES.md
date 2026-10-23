# Release Notes

## Unreleased

## 0.3.1 — 2026-10-22

This patch release corrects authorization, request handling, persistence and
runtime behavior. Upgrade affected vendored modules as described below.
Linux setup now builds and selects Arlen's pinned patched GNUstep runtime in
an Arlen-owned versioned prefix. Keep that prefix in place while installations
or services use it; see [Getting Started](GETTING_STARTED.md#manual-toolchain-setup).

Release qualification and remaining limitations are documented in the
[Known Risk Register](KNOWN_RISK_REGISTER.md).

- HTTP signal and console shutdown flags now use lock-free atomic accesses
  across handlers and worker threads.

- Runtime concurrency qualification now rejects server shutdown errors and
  sanitizer reports, and retains separate logs for every server generation.

- GNUstep app tests build and use the bundled XCTest library and headers
  together, including on clean toolchains without system XCTest.

- Session middleware added before auth-module registration now decodes cookies
  before session refresh and route policy, preserving current OIDC roles and
  sign-out enforcement on protected routes.

- Windows preserves HTTP parser errors and session/worker queue overload `503`
  responses with a bounded graceful close when rejected requests leave unread
  input queued in the socket.

- Request body deadlines and minimum rates are rechecked before accepting the
  final fragment on chunked and `Content-Length` readers. This closes a gap
  where late completion bypassed the clock; pipelined bytes do not increase
  the preceding body's rate, and failed uploads remove their spool files.
  Body clock settings also honor their documented zero values instead of
  silently restoring defaults.

- Linux automatic prerequisite setup pins the GNUstep bootstrap executable
  digest instead of trusting a checksum downloaded with the script.

- Deploy init restricts generated secret files before writing their contents
  and stops on permission errors, replacing the later best-effort chmod.

- Deploy doctor checks configured host-local PostgreSQL readiness in process
  through libpq instead of exposing the DSN in shell and `pg_isready` arguments.
  It fails closed if libpq is unavailable or the server is not ready.

- Propane keeps merged configuration secrets out of its Python parser process
  arguments while preserving unredacted worker settings.

- Jobs 1.1.4 enforces `allowManualEnqueue = NO` for API enqueue and dead-letter
  replay. Auth 1.7.2 uses `authModule.publicBaseURL` for queued mail links even
  when a job payload supplies another origin. Upgrade both vendored modules.

- EOC `yield` escapes an unfilled `content` slot's context fallback. The
  rendered page body captured by `ALNView` remains raw HTML in its filled slot.

- Negotiated template rendering no longer serializes template context as JSON
  when no JSON object is supplied. It returns `{}` for that branch and adds
  `Vary: Accept` to both HTML and JSON responses.

- Auth 1.7.4 requires recent MFA before an AAL1 session can view or verify a
  new TOTP enrollment when a verified SMS factor already exists. Factor
  discovery omits the new authenticator secret until step-up. Upgrade vendored
  auth modules before using SMS as a primary factor.

- Auth 1.7.5 retains the validated session generation after TOTP or SMS step-up,
  so normal step-up stays signed in at the new assurance level. Concurrent
  revocation makes step-up fail and clears the session. Password registration,
  sign-in, and change now preserve surrounding
  whitespace exactly, matching password reset and policy validation. Upgrade
  vendored auth modules.

- Auth 1.7.6 keeps session-schema metadata in the auth runtime instead of
  attaching it to a shared database adapter during requests. This removes the
  observed GNUstep class-pointer race during concurrent password resets.
  Replacing the adapter resets the cache; missing tables and failed probes
  remain retryable. Upgrade vendored auth modules and restart the app; this
  correction requires no new migration or configuration.

- Ops 1.1.1 removes individual jobs, notification outbox/fanout, and storage
  records from operator HTML and JSON summaries and drilldowns while keeping status
  metrics. Admins retain full detail. Upgrade vendored `ops` modules.

- Notifications 1.3.2 omits webhook URLs, headers, bodies, and error text from
  persisted outbox records and scrubs existing catalog rows at startup. Rotate
  older exports and backups separately if they contain webhook credentials.
  Upgrade vendored `notifications` modules.

- Admin UI 1.1.3 rejects executable and ambiguous resource link targets in
  HTML list and detail pages. Unsafe targets render as `#`; upgrade vendored
  `admin-ui` modules.

- MCP 1.0.6 filters `tools/list` by route policy, assurance, and authentication
  age metadata in addition to roles and scopes. Listing does not execute tool
  handlers or guards; calls retain full route enforcement. Upgrade vendored
  `mcp` modules.

- Synchronous HTTP compatibility helpers now reject invalid header names and
  CR/LF/NUL-containing values before connecting, on GNUstep and Apple paths.
  Invalid headers return `NSURLErrorDomain/NSURLErrorBadURL`; the configured
  HTTP client's existing invalid-request error remains unchanged.

- PostgreSQL numeric results, including array elements, and MSSQL decimal
  results reject text over 40 characters or 38 digits before Foundation
  conversion. Queries return a decode error and leave the connection usable.
  Select wider values as text when exact arbitrary precision is needed.

- Route path-prefix policies also apply to format-suffixed requests that
  dispatch to the protected route. Compiled fast routes now use the normal
  authorization path when assurance or authentication-age limits are set, and
  recognize string-valued path-prefix policies.

- Auth 1.7.3 refreshes and revokes signed sessions before `requireAuth` route
  policies run. Upgrade vendored auth modules before protecting routes solely
  with `security.routePolicies`.

- Admin UI 1.1.2 exports spreadsheet formula-like CSV cells as text, including
  configured column labels and values with leading whitespace. Upgrade vendored
  admin UI modules before opening exports in spreadsheet software.

- Parent `security.routePolicies` path prefixes apply to mounted child requests
  before forwarding. Parent session state is checked for `requireAuth`, and
  source IP rules use the original request path and peer. Exact mounted leaf
  prefixes also cover format-suffixed requests and nested mounts. Startup
  rejects enabled sessions anywhere in the mount tree that use the same cookie
  name with different secrets, including siblings and descendants behind a
  session-disabled app. Shared-session child cookie writes take precedence over
  parent legacy refresh cookies.

- Storage 1.4.2 refuses cached reads and downloads when the authoritative catalog
  cannot be reloaded. Backend exceptions release writer locks, discard
  uncommitted cached entries on the next reload, and remove the failed update's
  new attachment. Repair a corrupt catalog before retrying and upgrade vendored
  storage modules with `arlen module upgrade`.

- Auth 1.7.1 rejects `authModule.mfa.sms.testVerificationCode` outside
  development and test at startup. Remove this test bypass from production-like
  configuration and upgrade vendored `auth` modules.

- Search 1.2.2 applies resource visibility filters to PostgreSQL full-text
  results and their derived facets and suggestions. Upgrade vendored `search`
  modules before using tenant, soft-delete, or app-defined visibility rules
  with the PostgreSQL search engine.

- Storage module 1.4.3 creates Windows legacy plist catalogs with an owner-only
  protected DACL before writing and retains the last catalog on failed replacement.
  The canonical storage privacy regression now runs on Windows and POSIX.

- Chunked uploads on llhttp now enforce per-route decoded-byte limits and spool
  while receiving. Incremental decoding avoids repeated body parsing; encoded
  framing limits, body deadlines, and legacy rejection remain in force.

- Live keyed publishing requires explicit container and key arguments; broadcast
  payloads omit requester-specific live metadata and tracing IDs.

- ORM transaction exceptions clear the context's borrowed connection. Savepoint
  exceptions roll back inner writes before an outer transaction can continue;
  PostgreSQL and MSSQL close connections when that cleanup fails.

- Windows watch scans read each file's size and sub-second modification/change
  times together, preserving edit detection while avoiding delayed build-error
  recovery on large source checkouts.

- Redis URLs containing literal or encoded NUL are rejected before parsing.
- Template exceptions now restore per-thread render options and discard the
  failed render's composition slots, preserving any enclosing render state.

- Search 1.2.1 applies explicit and per-resource filters to promoted results.
  Filtered queries no longer include promotions that contradict those filters.
  Upgrade vendored `search` modules with `arlen module upgrade`.
- Windows watch mode now stops both app and build-error servers when its
  watch process tree is force-killed, releasing their listen ports even for
  direct CLANG64 shell launches.
- Windows installer fixtures serialize saved-user-PATH checks across
  checkouts, retaining current-shell and fresh-shell certification.
- Auth 1.7.0 rejects `registration.autoLogin = YES` outside `development` and
  `test`, because immediate sign-in reveals registered addresses. Production-like
  apps with local passwords and mail also reject `mailDispatch.mode = "synchronous"`
  because delivery latency can reveal account membership. Remove these settings,
  use the generic registration flow and durable mail jobs, then upgrade vendored
  auth modules.

- Multi-worker state diagnostics now require an explicit `state.durable = YES`
  declaration in production-like environments. A database URL or deploy
  database contract alone no longer clears the warning. Review app-owned
  request-spanning stores before adding the declaration; the check records
  intent and does not verify store durability.

- Notifications 1.3.1 removes `Reply-To`, `Resent-*`, and other address-bearing
  mail headers when a signed-in user queues a notification for themselves.
  Upgrade vendored notification modules with `arlen module upgrade notifications`;
  admin AAL2 and app-owned runtime queue paths retain definition headers.

## 0.3.0 — 2026-10-19

This release combines the public audit fixes and security hardening work. It
changes several authentication, persistence, and deployment defaults; review
the upgrade notes below before replacing an existing installation.

Known limitations remain documented in the [Known Risk Register](KNOWN_RISK_REGISTER.md),
including unresolved, non-blocking ThreadSanitizer findings.

- Concurrent requests now synchronize access to the cached largest per-route
  request-body limit. Mounted applications are inspected outside the cache lock,
  so parent and child application locks are not nested.

- Auth 1.6.1 moves registration verification and password-reset mail to durable
  `auth_mail` jobs when the durable adapter is configured. Production-like apps
  with local passwords and mail must install/configure the PostgreSQL jobs
  adapter, set `authModule.publicBaseURL`, and run the jobs worker. New-user
  creation and its mail enqueue commit together; auth and jobs must use the
  same PostgreSQL database and search path. Apply
  `tools/migrations/jobs/001_postgres_jobs.sql` before starting workers. Enqueue
  failures roll back new registrations and return a generic 503. Explicit
  `authModule.mailDispatch.mode = "synchronous"` preserves legacy delivery with
  its account-enumeration timing risk. Review [Auth Module](AUTH_MODULE.md) and
  [Durable Jobs](DURABLE_JOBS.md) before upgrading. Custom registration hooks
  still need their own timing review.

- Jobs operator-state reads now refresh shared state, and mutations use short
  cross-process transactions. Run one scheduler: scheduler bookkeeping and job
  enqueue are still separate operations.
- Ops 1.1.0 and Search 1.2.0 mark the changed module sources for
  `arlen module upgrade`. Ops dashboard history updates use cross-process
  transactions.
- Search 1.2.0 state transactions reject stale rebuild and incremental results with
  `state_conflict`. Replay claims expire after five minutes and require
  idempotent operations. External search engines still need one reindex writer
  per resource unless the backend provides publication fencing. See
  [Search Module](SEARCH_MODULE.md) for the full contract.
- Notifications 1.3 persists individual inbox/outbox/fanout entries and recipient
  preferences in SQLite, with one-time legacy plist import. Inbox and preference
  mutations refresh authoritative shared state; corrupt or unreadable persistence
  fails closed. Stop all older workers and back up before upgrading. Linux needs
  `libsqlite3-0`; see [Notifications Module](NOTIFICATIONS_MODULE.md) for migration,
  backup, retention and remaining in-memory merge costs. Preserve the catalog
  initialization marker with backups; it prevents stale plist reimport after
  catalog loss.


- Windows file responses accept valid Unicode filenames using wide-character
  filesystem calls. Framework/app/test builds now use 64-bit file offsets,
  preventing metadata and Range truncation above 2 GiB; rebuild custom CLANG64
  integrations with `_FILE_OFFSET_BITS=64`. Pinned file responses clone the same
  file object with independent positions, avoiding shared-offset read races.

- Storage 1.4 streams verified filesystem downloads, supports ranges/HEAD and
  checksum ETags, and bounds variant source materialization to 16 MiB by default.
- Storage persistence now uses per-record SQLite transactions and one-time legacy
  plist import. Stop old workers before upgrading; Linux requires `libsqlite3-0`.
  See `docs/STORAGE_MODULE.md` for migration, backup, and custom-adapter limits.
- `arlen deploy push|release|dryrun --json` now parses the packaging command's
  stdout independently of compiler warnings on stderr. Successful builds no
  longer report a false `deploy_push_failed` when those warnings appear.

- Request metrics now store primitive numeric values and batch completion
  counters/timings under one lock, reducing lock and allocation overhead (#249).
- PostgreSQL ORM-generated reads skip release-time session reset; raw/trusted
  expressions and transactions continue to reset (#306).

- PostgreSQL supports bounded cursor enumeration through
  `enumerateQuery:parameters:batchSize:usingBlock:error:`. It processes a batch
  at a time, supports early stopping, and cleans up on errors or exceptions.
- Apps configured with multiple propane workers and request rate limiting now
  warn that the request budget is per worker. Use an ingress limiter for a
  deployment-wide budget (#252).

- Normal HTTP responses now have a total send deadline (300 seconds) and
  minimum average rate (1024 bytes/second after 10 seconds). The limits cover
  headers and file or in-memory bodies; a miss closes the connection and frees
  its worker. Configure them under `requestLimits.responseSendTimeoutSeconds`,
  `responseMinBytesPerSecond`, and `responseMinRateGraceSeconds`. SSE and
  WebSocket sessions retain their separate policies. A failed partial `writev`
  is no longer retried by replaying already-sent response bytes (#304).

- Dataverse: `ALNDataverseCurlTransport` passes request headers, including the
  bearer token, to curl as a config file on stdin (`--config -`). They are no
  longer on curl's command line, which any local user can read through `ps` or
  `/proc/<pid>/cmdline`. The request-body file, which holds the client secret
  for token requests, is created owner-only (0600). The new
  `curlExecutablePath` property picks the curl to run (default: `curl` from
  PATH).
- Dataverse: the request method must be an HTTP token. A method with
  whitespace or control characters fails with
  `ALNDataverseErrorInvalidArgument` in `performRequestWithMethod:` before a
  token is requested or anything is sent, and `ALNDataverseCurlTransport`
  rejects it too.
- Route policies: `pathPrefixes` and `sourceIPAllowlist` given as one string
  now mean a one-element list. Before, a string turned into an empty list, and
  that silently switched the policy's check off. A list that is present but
  empty fails startup with `empty_list`, and any other type fails with
  `invalid_type`. The middleware denies a request (`invalid_policy_config`)
  rather than skip the source-IP check for such a policy.
- Dataverse: header names must be tokens, and header values must not contain
  control characters other than a tab. That covers caller headers, `ifMatch:`,
  and `$batch` part headers. In a `$batch` part, the method must be a token,
  the path must not contain whitespace or control characters, and the
  Content-ID must not contain control characters. Requests that break these
  rules fail with `ALNDataverseErrorInvalidArgument` before anything is sent.
  `ALNDataverseCurlTransport` checks the headers it is handed too.
- Dataverse: `invokeFunctionNamed:` percent-encodes parameter values inside
  their OData literal, the same way as alternate keys. Function and action
  names must be identifiers (optionally namespace-qualified, such as
  `Microsoft.Dynamics.CRM.WhoAmI`), and so must parameter names. `boundPath:`
  segments must be identifiers or `entitySet(<GUID>)`. Anything else fails
  with `ALNDataverseErrorInvalidArgument` before a request is sent.
- Dataverse: `recordID:` accepts only a GUID (a canonical GUID string or an
  `NSUUID`). Any other value, including the `(key=value)` and `key=value`
  forms, now fails with `ALNDataverseErrorInvalidArgument` before a request is
  sent; use the `alternateKeyValues:` methods for alternate keys. Alternate-key
  values are percent-encoded inside their OData literal. The curl transport
  passes `--path-as-is`.
- Forwarded client IPs: behind a trusted proxy, the client is now the
  right-most `X-Forwarded-For` hop that is not itself a trusted proxy. Proxies
  append the peer they saw, so the left-most value is whatever the client sent.
  It used to be the left-most value. This applies to both the request's
  `effectiveRemoteAddress` (and so the rate limiter) and route-policy
  `sourceIPAllowlist` checks, which now share one parser.
  - Hops must be IP addresses. An unreadable chain leaves the proxy's address
    on the request, and denies a protected allowlist check.
  - Route policies no longer read a `Forwarded` header unless
    `security.forwardedClientIPHeader = "Forwarded"` is set. They used to
    prefer it over `X-Forwarded-For`. The setting also picks the header the
    server's `effectiveRemoteAddress` comes from, so every reader uses one
    header.
  - Repeated `X-Forwarded-For` or `Forwarded` field lines are combined in order
    with ", " (RFC 9110), in both HTTP parsers. Before, only one of the lines was
    kept.
  - `trustedProxyCIDRs` and `ARLEN_TRUSTED_PROXY_CIDRS` accept IPv6 ranges.
    IPv4-mapped addresses (`::ffff:10.1.1.1`, which a dual-stack listener
    reports for IPv4 peers) count as the IPv4 address, for proxy matching,
    allowlists and the rate limiter's key.
  - The rate limiter tracks at most 65,536 clients at once. It evicts the
    oldest window first, in constant time per request. It counts IPv6 clients
    per `/64` by default (`rateLimit.ipv6PrefixLength`).
  - **Upgrade:** with more than one proxy in front of Arlen (for example a load
    balancer and then nginx), list every proxy in `security.trustedProxies` and
    `trustedProxyCIDRs`.
- CSRF protection now follows sessions. When `csrf.enabled` is unset, it is on
  whenever `session.enabled = YES`, in every security profile. Before, the
  `balanced` and `edge` profiles filled in `NO`, and `arlen new` wrote
  `csrf.enabled = NO` into `config/app.plist`, so an app that turned sessions
  on (as the `auth` module needs) accepted cross-site form posts. New apps no
  longer pin it.
  - **Action for existing apps:** delete `enabled = NO;` from the `csrf` block in
    `config/app.plist` if the app uses sessions. Browser forms then need the
    token: `-[ALNContext csrfToken]` in a hidden `csrf_token` field or the
    `x-csrf-token` header.
  - The `auth` module refuses to start when sessions are on and CSRF is pinned
    off, naming `csrf.enabled` in the error; `authModule.allowWithoutCSRF = YES`
    opts out. `arlen module doctor` reports the same case as
    `module_csrf_disabled`.
- ORM: a persisted model's primary key can no longer change. A changeset or
  `setObject:forFieldName:error:` that writes a different key fails with
  `ALNORMErrorReadOnlyMutation`; an unchanged key is still accepted. `UPDATE`
  and `DELETE` target the key as it was loaded or last saved. Before, a request
  payload with another row's `id` passed through
  `applyInputValues:error:` and `saveModel:changeset:` updated that row. The
  Dataverse ORM applies the same rule to a persisted record's primary ID.
  - New `-[ALNORMChangeset applyInputValues:permittedFields:error:]` casts only
    the listed fields and drops other input keys. Use it for request payloads
    so clients can't mass-assign foreign keys or role fields;
    `docs/ARLEN_ORM.md` now shows it.
  - `persistedPrimaryKeyValues` and `hasPersistedSnapshot` are now reserved
    generated-property names.
  - A model loaded without its primary key (a `selectFields:` that leaves it
    out) can't be given one: the setter and changesets refuse, and
    `saveModel:` and `deleteModel:` fail with `ALNORMErrorMissingField`
    instead of targeting whatever key the model holds. Select the key when
    you mean to write the row back.
  - Dataverse: `saveModel:`, `deleteModel:` and `saveModelsInBatch:` PATCH and
    DELETE the new `persistedPrimaryIDValue` (the ID as loaded). A persisted
    record loaded without its ID refuses those writes with
    `ALNORMErrorMissingField`; before, a save created a duplicate record. New
    `-[ALNORMDataverseChangeset applyInputValues:permittedFields:error:]`
    matches the SQL changeset. An update the server answers with `204` (no
    representation) keeps the model's fields and ID, so later saves still
    target the same record.
- The `storage` module (`1.4.0`) keeps one consistent catalog across
  processes sharing a local persistence path, such as propane workers and the
  jobs worker:
  - Changes refresh shared state under an exclusive application lock and commit
    changed catalog records in SQLite. Reads detect other processes' commits.
  - Object and upload-session IDs are random (`obj-<32 hex>`,
    `upload-<32 hex>`) instead of per-process counters.
  - Download tokens are bound to the object they were issued for.
  - Download tokens issued before the upgrade are rejected; they expire within
    `downloadTokenTTLSeconds` anyway. Existing objects keep their IDs.
  - Attachment data is shared too. With persistence on and no attachment
    adapter configured, the module uses a filesystem adapter at
    `<state file without extension>-attachments/` instead of the in-memory
    default, and it refuses to start with an explicitly configured in-memory
    adapter.
  - Downloads and variant jobs verify the attachment's size and SHA-256
    against the object record and answer 404 on a mismatch.
  - A change waits at most `storageModule.persistence.lockTimeoutSeconds`
    (default 10) for the state lock, blocking on it rather than polling, and
    then fails with the new `ALNStorageModuleErrorStateBusy` (HTTP 503). Only
    the catalog update runs under the lock: attachment data is written and
    hashed first, and deleted again if the catalog update fails.
  - Startup waits up to `persistence.startupLockTimeoutSeconds` (default 60)
    for its cleanup pass, and starts anyway, with a warning, if the lock is
    still busy.
  - Deletes remove an attachment only when its size and SHA-256 match the
    record.
  - Catalog files are owner-only (`0600` on POSIX; a protected current-user
    DACL on Windows). SQLite journals provide transaction recovery.
  - Legacy XML and binary plists are imported once. SQLite is the default;
    there is no silent fallback to whole-plist writes. See the migration and
    rollback instructions in [Storage Module](STORAGE_MODULE.md).
  - Downloads and other reads no longer take the state lock: they reload a
    changed file without it, and serve the in-memory catalog while a writer
    is busy.
  - The 503 for a busy state lock carries `Retry-After: 1`.
  - With persistence off and `propaneAccessories.workerCount > 1`, startup
    (outside `test` and `development`), `propane` and `arlen module doctor`
    warn that each worker keeps its own catalog.
- `ALNApplication.usesDefaultAttachmentAdapter` reports whether the
  attachment adapter is still the in-memory default, and the in-memory
  attachment adapter reports `processLocal = YES` in its capabilities.
  `ALNPlatformOpenExclusiveLockWithTimeout()` waits for a lock for at most a
  given time (a blocking wait on a helper thread, started only when the lock
  is contended), and both lock functions retry interrupted waits.
- Windows: `propane` now fails immediately with an unsupported-production
  diagnostic and status 2; `--help` still works. Windows remains a development
  platform. Previous multiworker preview behavior depended on unsafe port sharing;
  exclusive socket binding is now enforced. Use `boomhauer` for development.

- **Breaking (production):** `/metrics` and `/clusterz` answer `404` in the
  `production` environment until access is configured with
  `observability.operabilityToken` / `ARLEN_OPERABILITY_TOKEN` or
  `observability.operabilityLoopbackOnly` / `ARLEN_OPERABILITY_LOOPBACK_ONLY`.
  Before, both were anonymous by default, and `/clusterz` reports the hostname
  and worker layout. To keep the old behaviour behind a proxy that already
  blocks them, set `observability.operabilityAnonymous = YES` (or
  `ARLEN_OPERABILITY_ANONYMOUS=1`). `arlen doctor --env production` reports
  which mode is active, and `validate_operability.sh` sends
  `ARLEN_OPERABILITY_TOKEN` when set (#215).
- CI: a nightly `linux-sanitizers / integration-sanitizers-nightly` job runs
  the integration suite against an ASAN+UBSan build (clang's shared runtime,
  per-process reports under `build/sanitizers/integration_nightly/`). It skips
  the app-root tests listed in
  `tests/fixtures/sanitizers/integration_nightly_skips.txt`, which
  `tools/ci/classify_sanitizer_integration_skips.py` maintains, and is not a
  required check (#271).
- Outside `development` and `test`, `session.secret`, `auth.bearerSecret` and
  `storageModule.signingSecret` now refuse placeholder values (containing
  `replace-with`, `change-me`, `changeme`, `change_me` or `0123456789ab`) and
  secrets committed in the Arlen repository. They used to pass whenever they
  were 32+ characters, including the `site.env.example` placeholder. The env
  example now uses `CHANGE_ME`, `arlen deploy init` writes a freshly generated
  64-hex `ARLEN_SESSION_SECRET` into its `0600` env example, and the example
  apps keep their session/bearer secrets in
  `config/environments/development.plist`. The `storage` module is now `1.2.0`.
  Generate secrets with `openssl rand -hex 32`.
- Search module `1.1.0`: the Meilisearch and OpenSearch adapters encode
  record identifiers and index names in request URLs with only unreserved
  characters, and reject an identifier or index name that is empty, `.` or
  `..` with a validation error instead of sending the request. A record whose
  identifier was `..` used to turn a live-sync document delete into a request
  for the whole index (`DELETE /<index>/`). Arlen's libcurl HTTP transport
  (GNUstep) now sets `CURLOPT_PATH_AS_IS`, so it never collapses `.`/`..`
  path segments.
- Storage module `1.3.0`: declared content types must be a single media type (no lists, quotes or control characters) and are stored normalized; `GET /storage/api/download/:token` sends only that normalized type, and now sends
  `Content-Disposition: attachment` with a sanitized filename,
  `Content-Security-Policy: sandbox` and `X-Content-Type-Options: nosniff`.
  Only PNG, JPEG, GIF, WebP, AVIF, PDF, audio and video objects are served
  inline. Downloads used to be served inline with whatever content type the
  uploader declared, so an HTML or SVG object opened as a page on the app's
  origin. Wildcard `acceptedContentTypes` (`*/*`, the default, and `image/*`)
  no longer match `text/html`, `image/svg+xml` or `application/xhtml+xml`;
  collections that store them must list them exactly.
- EOC: when no page fills a named slot, `<%@ yield "name" %>` falls back to
  the context value with the same name. That value is now HTML-escaped like
  `<%= %>` output; it used to be written raw, so a controller value such as
  `title` could add markup to the layout. Slot content filled with
  `slot`/`endslot` and the plain `<%@ yield %>` page body are still emitted
  as-is.
- **Breaking (non-development environments other than `production`):**
  environments other than `development` and `test` (`staging`, `qa`,
  `preview`, ...) now get the same defaults as `production`: a `Secure` session
  cookie, no `/openapi` docs UI, no performance timing logs or `X-Arlen-*-Ms`
  headers, and `/readyz` failing while migrations are pending. Before, only an
  environment named exactly `production` got them. An explicit setting still
  wins, e.g. `session.secure = NO` for a staging site served over plain HTTP.
- **Breaking (production):** an app whose configured module fails to load or
  configure now refuses to start outside the `development` and `test`
  environments. The server and `jobs-worker` exit non-zero with
  `startup failed: module <id> failed to load: <reason>`. Before, the app logged
  one `module load skipped` warning, loaded no modules at all, and kept serving
  its own routes. In `development` and `test` the app keeps serving and logs
  `module load failed` at error level, naming the module, its config key and
  the modules not loaded; modules loaded before the failing one stay loaded.
  `arlen module doctor` adds a `module_sessions_disabled` warning for a module
  that needs sessions while `config/app.plist` sets `session.enabled = NO`
  (#294).
- `propane` no longer respawns a worker that fails at startup in a tight loop.
  It prints each distinct startup error once (`worker startup failed (same
  error) xN` for repeats), backs off exponentially from `respawnDelayMs` up to
  the new `respawnBackoffMaxMs` propane accessory (default 30 s), and after
  `startupFailureLimit` consecutive startup failures (propane accessory,
  default 5) exits with status `3` so the service manager reports a failed
  unit. Workers report startup errors through `ARLEN_STARTUP_FAILURE_FILE`,
  which propane sets (#294).
- On macOS, `propane` no longer exits early if a worker disappears while `lsof`
  samples its file descriptors. It continues reaping the worker and applies the
  configured startup-failure limit and backoff.
- A module load error names the config key whether the module reports it as
  `key_path`, `config_key` or `keyPath`, including on an underlying error.
- Environment names are classified once, ignoring case and surrounding
  whitespace: `ALNEnvironmentKindForName()` and
  `ALNEnvironmentIsDevelopmentLike()` in `ALNConfig.h`. Core uses them for the
  module-load startup check and the detailed error page, and the `auth`
  (OIDC loopback redirects), `jobs`, `notifications`, `search` and `storage`
  modules use them for their development/test checks (`auth` 1.5.4, `jobs`
  1.1.2, `notifications` 1.1.4, `search` 1.0.5, `storage` 1.1.3).
- Config loading normalizes the environment name (trimmed, lowercased) before
  choosing `config/environments/<name>.plist`. Before, `--env PRODUCTION`
  counted as production but skipped `production.plist`, so its overrides
  silently did not apply. `application.environment` and
  `config[@"environment"]` hold the normalized name
  (`ALNNormalizedEnvironmentName()` in `ALNConfig.h`).
- Vendored modules that are older than the framework's copy are now reported.
  `arlen doctor` and `arlen module doctor` warn with `module_outdated`
  (vendored → available version, and the fix: `arlen module upgrade <id>`,
  then `arlen module migrate`, then rebuild), and apps log
  `vendored module is older than the framework copy` at startup outside
  `test` when `ARLEN_FRAMEWORK_ROOT` is set. `boomhauer` now exports
  `ARLEN_FRAMEWORK_ROOT` to the app process, as `propane` and `jobs-worker`
  already did, so the warning also appears in development. Upgrading Arlen alone does not
  update modules an app has vendored with `arlen module add`; see
  [Modules](MODULES.md#6-upgrade-a-module).
- Request bodies now have bounds too, on both parsers and on the spool path
  for large bodies. `requestLimits.requestBodyTimeoutSeconds` (default `300`,
  env `ARLEN_REQUEST_BODY_TIMEOUT_SECONDS`) caps the total time to send a body
  after its head, and after `requestBodyMinRateGraceSeconds` (default `10`)
  the body must average at least `requestBodyMinBytesPerSecond` (default
  `1024`). A body that misses either gets `408`, and its spool file is removed.
  Before, a client trickling a body could hold an HTTP worker indefinitely.
  **Behavior change:** uploads slower than 1 KiB/s on average, or taking more
  than 5 minutes, now fail with `408`; raise or set `0` for the limits if your
  clients need that.
- New `requestLimits.requestHeadTimeoutSeconds` (default `15`, env
  `ARLEN_REQUEST_HEAD_TIMEOUT_SECONDS`) bounds the total time to receive a
  request head; a slower head gets `408`. For a connection's first request it
  counts from accept, so connections that send nothing, or that waited for a
  worker, are covered and can't stack; later keep-alive requests count from
  their first byte. Before, only each read was bounded by
  `connectionTimeoutSeconds`, so a few clients trickling one byte at a time
  (or sending nothing) could hold every HTTP worker. Both parsers apply it.
- File responses (`renderFileAtPath:`, `ALNFileResponse`) and static mounts
  answer 404 for a path that contains a control character (U+0000-U+001F or
  DEL) instead of passing it to the filesystem. A C path ends at U+0000, which
  JSON and multipart strings can carry, so a name checked as
  `report\u0000.pdf` reached `report`. Format characters such as U+200D,
  which emoji file names use, are still allowed. The same check now covers
  writes: `-[ALNUpload writeToFile:error:]` fails with an error, and
  `ALNPlatformOpenFile` / `ALNPlatformOpenExclusiveLock` fail with `EINVAL`,
  for such a path (new `ALNPlatformPathHasNoControlCharacters()`).
- An exception raised in middleware, or in the request or auth contract
  stages before the controller, now answers that request with a 500 (the
  normal error page or JSON; no exception details outside development and
  test) and is logged as `middleware exception`, `request_contract exception`
  or `auth_contract exception`. Before, only controller exceptions were
  caught, and one raised earlier ended the server process. As a last resort,
  an exception that escapes request handling now closes only that connection.
- Pipelined HTTP/1.1 requests on one connection each keep their own headers.
  On the llhttp parser, headers outside the small set copied at parse time
  (Host, Authorization, Origin, Content-Type, User-Agent and others) were read
  lazily from the connection buffer, which by then held the next pipelined
  request, so they came back truncated, empty or from that next request. A
  request now keeps its own copy of the header bytes, which also ends its
  dependence on the connection buffer's lifetime.
- `ALNPg` resets a connection's session state when it goes back to the pool
  after the borrower ran its own SQL (any `executeQuery`/`executeCommand`/
  script/prepare with caller SQL, a transaction, or a builder statement with a
  trusted expression): `RESET ALL`, `SET SESSION AUTHORIZATION DEFAULT`,
  `CLOSE ALL`, `DISCARD TEMP`, `DISCARD SEQUENCES`, `UNLISTEN *`,
  `pg_advisory_unlock_all()`. Settings such as `search_path`, `SET ROLE` or a
  `set_config` tenant ID, temporary tables, `currval`/`lastval`, `LISTEN`s
  and session advisory locks no longer carry over to the next borrower, and
  notifications still queued for the old `LISTEN`s are dropped. The pool's
  cached prepared statements are checked against `pg_prepared_statements` in
  the same round trip and all deallocated if one was replaced, so a borrower
  cannot change what a cached statement name runs for later borrowers. A
  connection released inside a transaction (including one opened by sending
  `BEGIN` by hand) is now closed instead of reused. A connection that only ran
  generated builder statements is reused without a reset. The new
  `sessionResetPolicy` chooses `Session` (default), `DiscardAll` or `None`.
  The reset costs one round trip (about 95 µs on a local socket).
  `poolDiagnostics` adds `released_in_transaction_count`,
  `session_reset_count` and `session_reset_failure_count`.
- `ALNPg` and `ALNMSSQL` refuse SQL text (and `ALNPg` statement names) that
  contain U+0000 with an invalid-argument error instead of letting the driver
  end the statement at the NUL.
- `ALNMSSQL` binds text parameters with their byte length instead of
  `SQL_NTS`, so a value with an embedded U+0000 reaches SQL Server whole
  instead of being cut short, and multi-byte text declares its UTF-8 length.
- `ALNPg` refuses a string parameter containing U+0000 with
  `ALNPgErrorInvalidArgument`. Before, libpq cut the value short at the NUL,
  so the database matched a different value than the app had checked. Send
  binary data as `NSData` (bound as `bytea`).
- `auth` 1.6.0 refuses a TOTP code whose time step was already accepted for the
  enrollment, even in another session, and limits failed verification
  attempts. Five consecutive failed TOTP or recovery-code checks lock MFA for
  that account for 30 seconds, doubling with each further failure up to 15
  minutes; a success resets the count. Failed password sign-ins are counted per
  submitted email and client address: after five, that pair waits 30 seconds,
  doubling up to 15 minutes, and a success clears only that pair. An
  account-wide ceiling against distributed guessing adds a wait for an email
  after 50 failures in an hour from all addresses. Password counters are keyed
  by the submitted email, so known and unknown emails behave the same. A pair
  that signed in successfully in the last 30 days skips the account-wide
  ceiling (`trustedPairDays`), and a successful sign-in never re-arms the
  account-wide wait. Waiting requests answer `429` with
  `Retry-After`. Forgot-password is never held back by these delays; it has
  its own send limit (5 per email and 20 per address per hour by default,
  under `authModule.attemptLimits.mail`), beyond which it replies as usual but
  sends nothing. Limits are set under `authModule.attemptLimits`. A verified
  enrollment now also accepts one of its recovery codes at the TOTP
  challenge, once each; they were issued but could not be used before. Run
  `arlen module migrate` to apply the new auth migration
  `004_auth_totp_limits`; until it is applied, verification works as before and
  the module logs one warning.
- `ALNPg` recovers from connections the server closed while they were idle
  (restart, failover, idle timeout, `pg_terminate_backend`). Such a failure is
  reported as `ALNPgErrorConnectionFailed` with the new
  `ALNPgErrorConnectionLostKey`, whatever SQLSTATE (or none) the result
  carried, and the connection is closed and never reused. On a connection
  from the idle list, the pool retries a plain read once on a new
  connection; a write only when the statement had not been sent
  (`ALNPgErrorStatementNotSentKey`: the connection was found closed before
  sending); nothing while a transaction is open. `withTransaction:` restarts
  only when `BEGIN` itself failed; the new
  `withTransactionReplayingOnConnectionLoss:` also replays the whole block
  once for blocks that are safe to run twice. `poolDiagnostics` adds
  `connection_retry_count`. The auth module
  treats these failures, and any database failure without a SQLSTATE, as the
  database being unavailable (`503` with `Retry-After`), never as a failed
  sign-in, and no longer passes driver messages to clients.
- The auth module's connection pool size is now configurable
  (`authModule.database.maxConnections`, default 8, was a fixed 4), and a busy
  pool waits up to `authModule.database.acquireTimeoutSeconds` (default 2) for
  a connection. When the database is busy or unreachable, auth routes answer
  `503` with `Retry-After` instead of `401`, and the session is kept; password
  sign-in answers `503` instead of `Invalid email or password`.
- `notifications` 1.2.0: `POST /notifications/api/queue` queues only for the
  signed-in user. It sets the payload's `recipient` to the caller's subject and
  `email` to their own address, and answers `403` when the payload names
  another `recipient`, `recipientSubject`, `recipients` entry or `email`.
  Queueing for others over HTTP needs the `admin` role at AAL2, like
  test-send. Below that, after the definition runs the module replaces every
  channel's target with the caller's own (email to their account address,
  in-app and web push to their subject), so no payload key can choose who or
  where a notification goes; the `webhook` channel is left out unless the
  definition implements `notificationsModuleAllowsWebhookForSelfQueuedNotifications`.
  `ALNNotificationsModuleRuntime` calls from app code are unchanged.
- Signing in and completing step-up (`ALNAuthSession`
  establish/elevate, used by the auth module and the `ALNController` helpers)
  now start a fresh session. Keys stored before, including `_csrf_token`, are
  dropped, so a CSRF token issued before login no longer works after it; a new
  token is minted when next read and is returned by the auth module's login,
  registration and verify responses. Only `return_to` is kept. Apps that keep
  data in the session across login or step-up need to store it again
  afterwards.
- `ALNTOTP` adds `matchedTimeStepForCode:...`, which returns the time step a
  code matched (or `NSNotFound`), so callers can refuse reused codes.
- Auth module (`auth` 1.6.0): the stub OIDC provider is now available only in
  the `development` and `test` environments. Elsewhere it defaults off, its
  routes are not registered, and setting `authModule.providers.stub.enabled =
  YES` is refused (the auth module's configuration is rejected). Apps that relied on the stub outside
  development or test must configure a real provider or local passwords.
- Auth module: an explicitly empty OIDC `admission.allowedEmails` or
  `admission.allowedDomains` list now fails configuration instead of admitting
  every verified identity. Omit an unused list key.
- Auth module: password-reset and email-verification links are single-use
  even under concurrent requests; only one request can consume a given link.
  A successful password change (by reset link or the change-password route)
  now retires every other outstanding reset link for that user.
- Auth module: new reset and verification links store only SHA-256 token
  digests in PostgreSQL. Links issued before this upgrade with plaintext token
  rows no longer work; users can request a new link.
- Auth module: new `authModule.publicBaseURL` key. Password-reset and
  email-verification links are built from it instead of the request's `Host`
  header. When it is unset, `development` and `test` still fall back to the
  request host; other environments send no link and log an error, so set
  `authModule.publicBaseURL` before upgrading a production app that uses local
  passwords.
- `search` (`1.2.0`): an unscoped query (`GET /search`, `GET /search/api/query`)
  from a caller who may not query any registered resource now returns no
  results, autocomplete, suggestions or facets, with `total = 0`. It used to
  search every resource.
- `search` (`1.2.0`) and `admin-ui` (`1.1.0`): resources the search module
  auto-registers from `admin-ui` (`searchModule.adminUI.autoResources`,
  including the built-in `users` resource) now use `queryPolicy = role_gated`
  with `admin-ui`'s roles (`admin`), AAL2 and the resource's `list` operation
  check, instead of `public`. Anonymous and non-admin callers can no longer
  query them, and `GET /search/api/resources` no longer lists them for those
  callers. Only fields `admin-ui` displays (`list` or `detail`) are indexed and
  returned. Search resources can set the new `queryMinimumAuthAssuranceLevel`
  metadata, and `ALNAdminUIModuleRuntime` reports `accessRoles` and
  `minimumAuthAssuranceLevel`.
- Auth module (`1.6.0`): authorization now uses each user's current roles.
  The module resolves the session's user against `auth_users` on every request
  (one indexed query, nothing cached), so route contracts and the admin-ui,
  jobs and ops APIs see a role grant or revocation on the user's next request.
  Before, they used the roles stored in the session cookie at sign-in until the
  cookie expired, while only the HTML admin pages read the current roles. A
  session whose user was deleted is signed out. Running `arlen module migrate`
  after upgrading is recommended: the new `002_auth_session_stamp.sql` adds a
  per-user session stamp, and `bumpSessionStampForSubject:error:` ends every
  existing session for a user. Without it, roles are still read live and
  nothing fails; the stamp is skipped and one warning names the migration. OIDC resolvers can implement the optional
  `refreshSessionDescriptorForSubject:provider:error:` to keep provider
  sessions' roles current the same way. See
  [Auth Module](AUTH_MODULE.md#sessions-and-roles).
- Auth module (`1.6.0`): signing out now ends the session on the server. The
  session is recorded in a new `auth_revoked_sessions` table (migration
  `003_auth_revoked_sessions.sql`; running `arlen module migrate` is
  recommended), so another copy of the signed-out cookie no longer works, while
  the user's other devices stay signed in. Changing the password ends the
  user's other sessions and keeps the current one; a password reset by link
  and removing the SMS factor end other sessions too. New sign out everywhere
  routes (`POST /auth/logout/all`, `POST /auth/api/logout/all`) end every
  session of the user. New `authModule.session.absoluteLifetimeSeconds`
  (default 14 days) signs a session out that long after sign-in even when it
  is renewed by use. Without migration 003, signing out still clears the
  cookie and one warning names the migration. See
  [Auth Module](AUTH_MODULE.md#sessions-and-roles).
- `search` (`1.2.0`): the operator/admin guard on drilldown and reindex routes
  and `role_gated` resources check roles through the new
  `+[ALNAuth context:hasAnyRole:]`, so they use the user's current roles like
  the other modules.
- admin-ui (`1.1.0`, requires auth `1.6.0`): revoking the admin role through
  the users resource also ends that user's existing sessions (once the auth
  stamp migration is applied).
- `arlen test --app` (`boomhauer --build-tests`) works on Windows. It used to
  stop with "--build-tests currently supports GNUstep on Linux only"; the app
  test bundle is now `AppTests.dll`, built against the framework's vendored
  tools-xctest.
- A spooled request body (`request.body` above `requestLimits.spoolThresholdBytes`)
  reads as empty once the handler returns. On Windows its spool file used to
  stay on disk after a handler exception, because the leaked request kept the
  file mapped. Also on Windows, static and `renderFileAtPath:` ETags now use
  the NTFS file index and 100 ns write/change times: a same-size rewrite within
  a second used to keep its ETag, so a changed file could answer 304.
- On Windows, `arlen boomhauer`, `arlen propane`, `arlen jobs worker` and the
  other commands that run a shell step (`arlen build`, `check`, `test`,
  `perf`) work from a console window. They used to exit 1 at once with
  "echo: write error: Bad file descriptor": `arlen` started `bash` through
  `NSTask`, which gives the child no console, while passing it the console's
  handles. They worked only when output went to a pipe or file (CI, `| tee`).
  `arlen` now starts `bash` on its own console and returns its exit code.
  Ctrl-C stops the whole command (`bash`, the server and the app) and `arlen`
  exits 130; closing the window or ending `arlen` stops it too, so nothing is
  left holding the port.
- Windows (MSYS2 `CLANG64`) builds again, on the public gnustep-cli `v0.1.0`
  managed toolchain. `scripts/run_clang64.ps1` and the runtime now find that
  toolchain (or `ARLEN_MSYS_ROOT`, or `C:\msys64`) instead of assuming
  `C:\msys64`. Code added since the Windows lane last ran was made portable
  again (UTF-16 file paths, Winsock timeouts, no `getrlimit`/`pthread`/`execl`
  on Windows), apps built by `boomhauer` get the framework's Windows flags,
  and a pointer stored in an `unsigned long` (32 bits on 64-bit Windows) no
  longer truncates. Windows test lanes now run through the vendored
  tools-xctest runner (#116), and make no longer relinks every tool and
  rebuilds the framework on each run on Windows.
- On Windows, `boomhauer` started from a native process (the test runner, an
  app) no longer rebuilds the whole framework, header edits now rebuild the
  objects that include them, and `propane` no longer rejects its own config
  ("cluster enabled must be a boolean"). The repository now checks out LF
  line endings on every platform (`.gitattributes`). `phase24-windows-runtime-tests`
  passes, and the `windows-preview` workflow has a self-hosted runner (fork
  pull requests are not run on it).
- An OIDC authorization callback validated in the same clock tick its state
  was issued in could be rejected as "exceeded the configured age window":
  rebuilding `issuedAt` from seconds since 1970 left it ~1e-7 s in the future.
  Callbacks now allow 1 s of future skew. The same rounding made a job
  enqueued "now" in the file job adapter not due for an immediate dequeue.
  Both were common on Windows (GNUstep's clock there ticks in ~1 ms steps)
  and possible anywhere.
- On Windows, `ALNLogger` wrote to stderr even when `outputFileDescriptor`
  named another descriptor; boomhauer relinked the app on every build (the
  make target lacked `.exe`); and the notifications module's Web Push store
  did not compile (it now locks with `LockFileEx`). The unit test suite builds
  and runs on Windows.
- Release archives built without `build/obj` (the planned Windows zip) carry
  `build/.release-prebuilt`. While it matches the tree and toolchain,
  `bin/arlen` and `boomhauer` use the prebuilt framework instead of running
  `make` (`tools/release_prebuilt.sh`).
- `arlen new /absolute/path` creates the app at that path. It used to be
  nested under the current directory on every platform.
- `make` parses faster: module template paths no longer spawn a shell per
  template (about 0.3 s per invocation on Linux, about 15 s on Windows).
- JSON log lines are written from the serializer's UTF-8 bytes with the
  newline appended once. Before, each line was decoded to an `NSString`,
  appended to, and encoded again (two encodes and three copies). An access-log
  line costs about 10-15% less (#248). JSON serialization and synchronous
  sink coordination remain; this change removes the redundant encoding work.

- Busy keep-alive clients no longer lock out new connections (#187,
  PERF-07). #193 stopped idle keep-alive connections from holding HTTP
  workers. But clients that kept sending requests on persistent connections
  still held a worker each (8 by default), and every other client waited
  indefinitely. After a response, a worker now yields its connection to the
  idle-connection watcher whenever other connections are queued. The
  connection rejoins the end of the queue when its next request arrives, so
  workers take turns. A new request behind 16 busy keep-alive clients went
  from no response (10 s timeout) to about 1 ms. Single-client throughput is
  unchanged.
- Response headers are serialized into a byte buffer instead of an
  `NSMutableString`. GNUstep paid for a temporary `NSData` and an encoding
  check on each of about 80 appends per response. Serializing a typical
  19-header response is about 1.6-2x faster, and the bytes are unchanged
  (#245). Constant security headers are also validated and prepared once per
  middleware/application instance; public setters retain validation and ordered
  insertion avoids a redundant linear scan. Native Windows measurements of the
  construction followup reduced middleware benchmark time by about 32% and
  dynamic 32-header time by about 7%, with identical output byte totals.

- The vendored yyjson is updated from 0.12.0 to 0.13.0 (#269). That fixes
  upstream GHSA-f4vc-345x-4mvm: a number token with 2^32 or more significant
  digits could overflow a stack buffer. Arlen's default 1 MiB body limit kept
  HTTP input from reaching it. 0.13.0 also fixes an uninitialized read in
  number parsing.

- `arlen config` now prints secret values as `[redacted]`, in both text and
  `--json` output. A string is redacted when its key contains `secret`,
  `password`, `token`, `apiKey` or `connectionString` (for example
  `session.secret` and `database.connectionString`), and passwords inside
  URLs and DSNs (`postgres://user:pass@host`, `password=...`) are masked. The
  JSON shape is unchanged. Pass `--show-secrets` to print the real values;
  `propane` now does, since it reads its settings from `arlen config --json`
  (#225).

- Release activation and rollback now swap `releases/current` atomically. They
  used `ln -sfn`, which removes the old link before creating the new one, so a
  service restart or `propane` respawn in that window could find
  `releases/current` missing and fail to start. The new link is now created
  under a temporary name and renamed over `current` (`mv -T` with GNU
  coreutils, `mv -h` on macOS/BSD, `os.replace` otherwise) (#225).

- propane's file-descriptor pressure check no longer stalls the manager
  loop (#222). It counts a worker's descriptors with a shell glob, and it
  builds the per-target breakdown only when it is about to log a warning or
  retire the worker, using one `find` instead of one `readlink` per
  descriptor. That breakdown went from about 1.5 s to under 10 ms for a
  worker with 2000 descriptors. Before, the check ran for every worker every
  15 s whether or not anything was logged, and the manager couldn't reap,
  respawn or handle signals while it ran.

- WebSocket sessions no longer drop an idle receive-only client after
  `connectionTimeoutSeconds` (about 30 s) without a close frame. After
  `runtimeLimits.webSocketPingIntervalSeconds` (default 25) without a frame the
  server pings, and closes with 1001 a client that stays silent for another
  interval (#239).
- WebSocket frames follow RFC 6455 more closely (#214): control frames must be
  unfragmented and at most 125 bytes, nonzero RSV bits and reserved opcodes are
  rejected (all close with 1002), fragmented messages are reassembled up to the
  1 MiB message limit (1009 above it) instead of dropping the connection,
  invalid UTF-8 text closes with 1007 instead of becoming an empty message, the
  peer's close code is echoed, and payload buffers grow as bytes arrive
  instead of being allocated from the frame header.

- Request-path performance and robustness (#218, #247, #265, #270):
  - Multipart parsing is about 20x faster. Header-name and boundary checks use
    precomputed tables instead of rebuilding a GNUstep `NSCharacterSet` and
    its `-invertedSet` for every header line, and quoted parameter values are
    no longer built with `appendFormat:` per character. A 128-part form went
    from about 19 ms to under 1 ms to parse.
  - File responses format `Last-Modified` and `Date` with `gmtime` and fixed
    tables, and parse `If-Modified-Since` / `If-Unmodified-Since` /
    `If-Range` IMF-fixdates without building an `NSDateFormatter`. Two ICU
    formatters per static response were about 40% of static-file CPU. The
    obsolete RFC 850 and asctime forms are still accepted.
  - MSSQL text columns use the length the ODBC driver reports, so a value
    with an embedded NUL is no longer truncated.
  - The framework's demo `boomhauer` JSON endpoints (`/api/echo/:name` and
    others) escape route parameters. A quote or backslash in the path used
    to break out of the JSON string.

- Data layer fixes (#230, #231, #232, #237, #238):
  - `withTransaction` (and `commitTransaction:`) now fails when a statement
    inside the block had already aborted the transaction. PostgreSQL turns
    that `COMMIT` into a `ROLLBACK`, and Arlen used to report success while
    every write in the block was discarded. The transaction is rolled back
    and an error is returned.
  - The MSSQL dialect binds parameters in the order the `?` placeholders
    appear. A trusted expression that reorders or repeats `$N` used to bind
    the wrong values, or too few. A `$N` with no matching parameter is now a
    compile error.
  - `executeBuilderQuery` costs about 2.6x less per call. Query diagnostics
    events are only built when a listener or stderr output wants them, and
    the compile signature no longer triggers six caught KVC exceptions per
    query on a plain `ALNSQLBuilder`.
  - `ALNDatabaseInspector inspectSchemaMetadataForAdapter:` works on
    PostgreSQL again: the view inventory query ordered by the reserved word
    `table`, so ORM codegen metadata came back nil.
  - Read-after-write stickiness drops expired scopes as the map grows, so
    scopes that write and never read again no longer stay in memory forever.

- Event streams: SSE and websocket stream sessions subscribe before they
  replay and hold live events until the replay is sent. Events committed while
  a client connected were lost before, and concurrent appends could arrive out
  of order; appends now publish in commit order. Live events queue per session
  (up to 1024) and go out from the session's own thread, so a slow client no
  longer holds up appenders; a client that falls 1024 events behind is
  disconnected and resumes from its cursor. SSE `id:` is the stream sequence
  (it was the `event_id`), and `renderSSEStream:` resumes from a
  `Last-Event-ID` header when given no cursor (#240).
- `ALNInMemoryEventStreamStore` keeps at most `maxEventsPerStream` events per
  stream (default 10000) and optionally none older than `maxEventAgeSeconds`;
  it kept every event before. Replays start at the cursor instead of scanning
  the stream, and a cursor older than the oldest kept event gets
  `resync_required` (#242).

- HTTP request handling follows RFC 9110/9112 more closely (#211, #212, #213,
  #253):
  - Chunk-size lines no longer count toward `maxHeaderBytes`. A chunked body
    sent as many small chunks used to get `431`.
  - `Expect: 100-continue` gets an interim `100 Continue`. Clients such as curl
    used to wait about a second before sending the body. Other expectations
    get `417`.
  - An HTTP/1.1 request with two `Host` headers, or none, gets `400`. Before,
    the last `Host` won and a missing one was accepted. Clients that send
    HTTP/1.1 without `Host` must add it.
  - An absolute-form target (`GET http://host/path`) is routed by its path,
    and its authority becomes the `Host`. It used to return `404`.
  - `400`, `408`, `413`, `417` and `431` responses written before the
    application runs now carry the configured security headers.
  - The configuration reference now says that the default parser accepts
    chunked request bodies; it used to say they were rejected.

- Production defaults are tighter (#215, #244):
  - `performanceLogging` now defaults to off in `production`. A new
    `performanceHeaders` setting (`ARLEN_PERFORMANCE_HEADERS`), also off in
    `production`, controls the `X-Arlen-*-Ms` and `X-Mojo-Total-Ms` timing
    headers separately from the log. With both on, production paid about twice
    the CPU per request and every client got a timing oracle.
  - `arlen new` no longer writes `session.secure = NO` or
    `openapi.docsUIEnabled = YES` into the base `config/app.plist`, so
    production gets `Secure` session cookies and no OpenAPI explorer. Existing
    apps keep those keys until you remove them.
  - The detailed exception page appears only in `development` and `test`;
    `staging` and other environments now get the production error response.
- Accepted connections set `TCP_NODELAY`. File responses (static mounts and
  `renderFileAtPath:`) on a keep-alive connection waited about 40 ms each for
  the client's delayed ACK, capping one connection at about 22 file responses
  per second (#243).

- A job handler that raises an exception no longer escapes `ALNJobWorker`.
  Before, a throwing ("poison") job stopped the worker run, skipped the jobs
  after it, and with the in-memory adapter stayed leased forever. The exception
  now counts as a failed attempt: the job is retried with the usual delay and
  dead-lettered after `maxAttempts` (#241).

- Static mounts no longer serve hidden files. Any path component starting with
  `.` returns 404 (`/static/.secret.json`, `/static/.git/config.json`), except
  `.well-known/`. Before, `arlen new` apps served such files from `public/` in
  every environment whenever their extension was allowed (#219).

- `ALNPg` decodes `date`, `timestamp` and `timestamptz` values, and encodes
  `NSDate` parameters, with integer date arithmetic. It no longer creates an
  `NSCalendar` for each value it decodes or an `NSDateFormatter`, `NSCalendar`
  and `NSLocale` for each `NSDate` parameter. Decoding 300k timestamps is
  about 7x faster, and an `NSDate` parameter now costs close to what a
  string parameter does. Results for years 1583 through 9999 are unchanged. Earlier dates now
  use the proleptic Gregorian calendar, as PostgreSQL does. Before, they were
  decoded on the Julian calendar, which shifted them by up to 10 days from the
  stored value, and dates from 1582-10-05 through 1582-10-14 failed to decode.
  An `NSDate` before year 1 is now sent with PostgreSQL's ` BC` suffix
  instead of as the matching AD year. `infinity`, `-infinity` and BC values
  still fail to decode, as before (#233).

- `ALNPg` encodes and decodes `bytea` hex text through a lookup table over C
  buffers, and decodes `bytea` columns straight from libpq's result buffer.
  A 4 MiB value now takes about 0.03 s to insert and 0.01 s to select, down
  from about 0.5 s and 0.75 s. The hex text format is unchanged. Hex text
  with whitespace between digits is now rejected like any other non-hex
  character (#234).

- The `ALNPg` pool runs its `SELECT 1` liveness probe only on connections
  that have been idle for at least `connectionLivenessCheckIdleThreshold`
  seconds (default `30`). Before, it ran on every reuse, which added a round
  trip to every pooled statement. Every reused connection still gets libpq's
  free connection status check. Set the threshold to `0` to probe on every
  reuse as before (#236).

- `ALNRedisCacheAdapter` checks a cached value's binary property list before
  Foundation decodes it. The value must be in binary format (the only one the
  adapter writes), with no reference cycles, at most 64 nested containers, and
  at most a million objects (or four per payload byte, if larger) once shared
  references are expanded.
  Before, the adapter parsed any plist format, so a hostile Redis server (or a
  MITM on the plain-TCP connection) could send a deeply nested plist that
  Foundation's recursive parser cannot handle. Payloads that fail the check
  return error 2235. Values nested more than 63 levels deep can no longer be
  read back (#265).

- `ALNRedisCacheAdapter` keeps up to four idle connections per adapter and
  reuses them across commands and worker threads. `AUTH` and `SELECT` run once
  per connection. Before, every cache command opened a new TCP connection, ran
  `AUTH` and `SELECT`, and closed it, so each cache access paid a TCP handshake
  and up to three round trips and left a socket in `TIME_WAIT`. A connection
  that fails is closed rather than reused, and a command that fails on a
  pooled connection the server has dropped is retried once on a new
  connection (#223).

- `ALNRedisCacheAdapter` now stores cache entries without a TTL on macOS.
  Their record held `NSNull`, which Apple's property-list writer rejects, so
  `setObject:forKey:ttlSeconds:0` failed there (#223).

- The Redis reply parser bounds what it accepts: replies may nest at most 8
  arrays deep, bulk replies may be at most 512 MiB, and arrays at most 16Mi
  elements. Bulk replies are read in 64 KiB chunks and arrays grow as elements
  arrive, so a declared size no longer allocates memory up front. A reply
  outside these bounds fails the command with an `NSError`. Before, a deeply
  nested reply overflowed the stack and a huge declared bulk length
  allocated it in full (#224).

- The WebAuthn CBOR parser rejects array, map, byte-string and text-string
  lengths that exceed the remaining input, and no longer uses a declared
  count as a capacity hint. Before, a short `attestationObject` declaring a
  huge count or length raised an exception in
  `verifyRegistrationResponse:expectedOptions:error:` instead of returning
  `ALNWebAuthnErrorMalformedCBOR` (#229).

- The vendored cmark-gfm `autolink.c` picks up upstream commit `4682993`,
  which computes the offset of the character before a `mailto:` or `xmpp:`
  autolink with signed arithmetic. The old expression wrapped the pointer, which
  is undefined behaviour (UBSan reported it for input such as `<xmpp:@`), even
  though the byte read was correct (#254).

- EOC `<%= %>` escaping is much faster. `ALNEOCEscapeHTMLString` used to
  append each ordinary character with a format call; it now copies runs of
  characters, returns the input unchanged when there is nothing to escape, and
  `<%= %>` output is escaped straight into the page buffer. Output is
  unchanged: `& < > " '` are escaped exactly as before. On a 90,000-character
  string it is about 50 times faster (#216).

- New `ALNEOCJSONForScript(value)` helper for putting JSON inside an inline
  `<script>` element with `<%== %>`. It writes `<`, `>`, `&`, U+2028 and
  U+2029 as `\u` escapes, so a string value such as `</script>` cannot end
  the script element. See EOC Guide section 5.4 (#217).

- EOC collection rendering
  (`<%@ render "partials/_row" collection:$rows as:"row" %>`) now looks up
  the partial and builds the shared locals overlay once per collection
  instead of once per item, so long lists no longer take the global template
  registry lock for every row. Output and errors are unchanged (#246).

- Numbers that arrive as strings are now read on Apple Foundation. Query
  parameters such as admin-ui `?page=` and `?limit=`, jobs `?limit=`, and
  search `?limit=` and `?autocomplete_limit=`, and numeric settings in
  old-style (text) plists such as dataverse `maxRetries`, module `maxAttempts`
  and pagination limits, were silently replaced by their defaults on macOS:
  Apple's `NSString` has no `-unsignedIntegerValue`. The new
  `ALNUnsignedIntegerFromValue` and `ALNUnsignedIntegerValueOrDefault`
  (`ALNPlatform.h`) accept an `NSNumber` or a string of decimal digits
  (surrounding whitespace allowed; no sign, fraction, exponent or overflow).
  On GNUstep, a string that is not plain digits (such as `limit=abc` or
  `-1`) now gets the default; before, GNUstep read its leading number, or
  `0`. `admin-ui` and `ops` are now `1.0.3`, `auth` `1.5.3`, `jobs`
  `1.1.1`, `notifications` `1.1.3`, `search` `1.0.4` and `storage` `1.1.2`
  (#264).

- `tools/deploy/smoke_release.sh --port 0` picks a free port right before each
  health probe and, if propane's workers cannot bind it, retries on a new port
  (up to three attempts). The health probe's `curl` now times out after two
  seconds, so a stray listener on the probe port can no longer hang the smoke
  run. `DeploymentIntegrationTests` uses `--port 0`; it used to pick a port
  minutes before propane started and never checked the second probe port, so
  CI occasionally failed with `bind: Address already in use` (#170).


- Releases now include `arlen-X.Y.Z-windows-x64.zip`, a prebuilt Windows
  archive for the gnustep-cli managed MSYS2 `CLANG64` toolchain. It bundles
  `libpq.dll`, which the toolchain does not ship, and records the toolchain
  version it was built against. `SHA256SUMS` covers it and `install.ps1`. A
  new `release-certification / windows` job installs the zip with
  `install.ps1` and checks `arlen new`, the app build and `boomhauer` through
  the installed launcher (#200).

- `ALNPg` now decodes `json`/`jsonb` values that hold a scalar document (a
  string, number, boolean or `null`) instead of failing the whole query
  (#182).
- `tools/install.ps1`: a PowerShell installer for Windows that mirrors
  `install.sh`. It downloads `arlen-X.Y.Z-windows-x64.zip`, checks it against
  `SHA256SUMS`, and refuses a gnustep-cli managed CLANG64 toolchain whose
  version differs from the one the zip was built against. It installs to
  `%LOCALAPPDATA%\Arlen` and adds an `arlen.cmd` launcher (#200).

- `tools/deploy/build_release.sh` now works from a shell that hasn't sourced
  GNUstep.sh. On Linux it and `smoke_release.sh` source
  `tools/source_gnustep_env.sh` before they build and run binaries. Before,
  the freshly built `eocc` couldn't load `libgnustep-base` and the build
  stopped. `build_release.sh` also uses the same test as `propane` to decide
  whether an app has sources, so an app with sources but no `src/main.m` now
  ships its binary. Before, `propane` tried to rebuild that app from the
  release, which it can't do. Together these kept the `release-certification`
  workflow from ever passing (#181).

- `arlen typescript-codegen --target client,react` works for apps that
  don't use the ORM. Before, it always read `--orm-input` and required at
  least one ORM descriptor, even though the client and React targets only
  use the OpenAPI document. Now a missing default manifest is skipped for
  `client`, `react` and `meta`, and the package is generated from
  `--openapi-input` alone. `models`, `validators`, `query` and `all` still
  require descriptors, and an explicit `--orm-input` path must exist (#183).

- Idle keep-alive connections no longer hold HTTP workers. Before, each open
  keep-alive connection held one of the 8 default workers until its next
  request or the 30-second `connectionTimeoutSeconds`. A browser holds about
  six connections per site, so a page reload could wait up to 30 seconds.
  Now a worker hands an idle connection to a watcher thread after
  `runtimeLimits.keepAliveParkAfterMilliseconds` (default 5), and picks it up
  again when the next request arrives. `docs/CONFIGURATION_REFERENCE.md` now
  documents `runtimeLimits` and notes that server-sent event and WebSocket
  sessions still hold a worker while open (#187). Windows parks idle
  connections too: its watcher polls with `WSAPoll` and wakes on a loopback
  socket instead of a pipe (#200).

- `arlen typescript-codegen` output compiles in two more cases (#184):
  - Inferred ORM relations no longer reuse a column name on the same model. A
    relation that would shadow a column gets a `Record` or `List` suffix, for
    example `sectionRecord` or `notesList`. Explicit relation overrides that
    collide fail with a clear error.
  - `react.ts` query keys for operations without parameters name their
    argument `_request`, so the package compiles under `noUnusedParameters`.

- JSON that Arlen writes with sorted keys is now actually sorted, on both
  Linux and macOS. This covers `typescript-codegen` package files, `eocc`
  manifests, schema-drift and Dataverse codegen output, and `arlen` JSON
  reports. A `#ifdef NSJSONWritingSortedKeys` guard was always false
  because both Foundations declare the option as an enum constant, so
  output used dictionary hash order and differed between platforms.

- The `mcp` module has an explicit local-development identity,
  `mcp.development.trustLoopback`. It applies only to loopback requests with no
  credentials, `Origin` or proxy-forwarding headers, and is refused outside
  development/test, on a non-loopback host, or with `mcp.oauth`. The MCP docs
  now explain that app identity middleware must be registered from a plugin
  to run before the module (#185). `mcp` moves to `1.0.4`.

- The `search` module bounds the cost of a query. `q` longer than 256
  characters is rejected with `422` (`ALNSearchModuleErrorValidationFailed`)
  instead of being processed. "Did you mean" suggestions are skipped for
  queries over 64 characters, and `autocomplete_limit`/`suggestions_limit`
  are clamped to 25. The default engine's fuzzy matching builds the query's
  trigram set once per query, uses a plain C buffer for edit distance, and
  skips the edit-distance table when word lengths differ by more than two.
  Results for other queries are unchanged (#226). `search` moves to `1.0.3`.

- The `notifications` module caps its outbox (`outbox.maxEntries`, default
  1000) and each recipient's inbox (`inbox.maxEntriesPerRecipient`, default
  200); past the cap the oldest entries are dropped, including when a larger
  state file is loaded. The inbox (`GET /notifications/api/inbox`,
  `GET /notifications/inbox`, and the new
  `-inboxSummaryForRecipient:limit:offset:`) accepts `limit` and `offset` and
  returns a `pagination` object; without `limit` it still returns the whole
  (now bounded) inbox. Preference updates for an unregistered notification or
  an unknown channel are rejected with `422` instead of being stored. In
  notifications 1.3, these retention and validation changes are paired with
  incremental SQLite persistence (#227); see the upgrade instructions above.

- Module hardening (#228):
  - `/metrics` and `/clusterz` can be restricted with
    `observability.operabilityToken` / `ARLEN_OPERABILITY_TOKEN` (require
    `Authorization: Bearer <token>`) and
    `observability.operabilityLoopbackOnly` /
    `ARLEN_OPERABILITY_LOOPBACK_ONLY` (direct loopback requests only). Both
    stay anonymous by default; `arlen doctor --env production` now warns
    while they are.
  - MCP `tools/list` only lists tools whose required roles and scopes the
    caller holds. `tools/call` still enforces every route check. `mcp` moves
    to `1.0.5`.
  - Local-password login verifies a throwaway Argon2id hash when the email
    is unknown, so response time no longer shows whether an account exists.
    `auth` moves to `1.5.2`.
  - The notifications HTML inbox links an entry's `href`/`path` only when it
    is an `http`/`https` URL or a same-origin relative path; other values
    render without a link.
  - PostgreSQL search autocomplete escapes `%`, `_` and `\` in the query
    and uses `LIKE ... ESCAPE '\'`, so `q=%` no longer matches every
    document.

- Windows is now documented as a supported development platform, on the
  gnustep-cli `v0.1.1` managed MSYS2 `CLANG64` toolchain, which includes
  libcurl. The new `docs/GETTING_STARTED_WINDOWS.md` covers the toolchain,
  `install.ps1`, and building and running apps. README, the docs index, `WINDOWS_CLANG64.md`,
  `TOOLCHAIN_MATRIX.md` and `CLI_REFERENCE.md` carry the new support
  statement. Windows production (`propane`, `jobs-worker`, service deploys) is
  planned for 0.4.0 (#200).

## 0.2.1 — 2026-10-15

A patch release with two fixes found while preparing the 0.2.0 announcement.

- The installer's PATH hint now names the startup file your login shell reads
  (`~/.zprofile` for zsh, the macOS default) instead of `~/.profile`, which
  zsh ignores.

- The `boomhauer` build-error page shows its styling again. The app's
  default `default-src 'self'` CSP blocked the page's inline styles, so it
  rendered as unstyled text. The page now sends its own CSP, which allows
  inline styles and nothing else (#177).

## 0.2.0 — 2026-10-15

Arlen now installs with one command on Linux and Apple Silicon Macs, and
macOS is a supported development and production platform (build, test,
`boomhauer`, `propane`, `jobs-worker`, `perf` and launchd deploys), with the
full unit, integration and durable-jobs suites running in Apple CI. Linux
gains a public, rootless toolchain path through gnustep-cli. The
notifications module gains a Web Push channel.

- Stopping `arlen boomhauer`, `arlen propane` or `arlen jobs worker` now stops
  the server. `arlen` ran them as a child process, which `NSTask` puts in its
  own process group on both Apple and GNUstep, so a Ctrl-C (or a signal to
  `arlen`) ended `arlen` and left the server running and holding its port.
  `arlen` now execs these commands, so the server keeps `arlen`'s pid and
  process group.

- Install with one command. Each release now ships downloadable archives,
  and `curl -fsSL https://github.com/danjboyd/Arlen/releases/latest/download/install.sh | bash`
  installs Arlen to `~/.local/share/arlen/<version>` with an `arlen` launcher
  in `~/.local/bin`. Downloads are checked against `SHA256SUMS`.
  - Apple Silicon Macs (macOS 14 or later) get prebuilt framework tools, so
    nothing is compiled at install time. Intel Macs are not supported yet.
  - Linux gets a source archive that the installer builds once.
  - On Linux the launcher sets up the GNUstep environment, so there is no
    `source` step.

  The new `release-assets` workflow builds the archives and smoke-tests an
  install from each one. See `docs/GETTING_STARTED.md` and
  `docs/CLI_REFERENCE.md`.

- Linux has a public toolchain path. Arlen now works with the
  [gnustep-cli](https://github.com/danjboyd/gnustep-cli-new) managed
  clang/libobjc2 toolchain (stable `v0.1.0`), which installs without root.
  Arlen is verified with it on Debian 13 (amd64 and arm64) and Ubuntu 26.04
  LTS (amd64). The new `linux-public-toolchain` CI lane checks all three in
  clean containers. When
  `/usr/GNUstep` is absent, `tools/source_gnustep_env.sh` finds the toolchain
  under `~/.local/share/gnustep-cli` or `/opt/gnustep-cli`, and puts its
  `libdispatch` directory on `LD_LIBRARY_PATH`.

- `arlen doctor` no longer warns that `xctest` is missing when the vendored
  `tools-xctest` runner is present. That runner is what `arlen test` uses.
- macOS deploy targets run under launchd. For `macos-*-apple-foundation`
  targets `arlen deploy init` generates `launchd/<label>.plist` (from the new
  `tools/deploy/launchd/arlen.plist`) and propane/jobs-worker wrappers that
  export the target's env file, since launchd has no `EnvironmentFile`. The
  doctor checks the plist and `launchctl`. On macOS, `arlen deploy`
  `status`/`doctor` read the job with `launchctl print`, `restart`/`reload`
  default to `launchctl kickstart -k`/`kill HUP`, and `logs --service` tails
  `<releasePath>/logs/<label>.log`. `ARLEN_LAUNCHD_DOMAIN` selects a domain
  other than `system`. The default service name for macOS targets is
  `arlen.<target>` (GitHub issue 148).

- `arlen perf` runs on macOS. `tests/performance/run_perf.sh` builds the profile
  servers with the Apple toolchain (new `tools/build_apple_xctest.sh
  --tools-only`), runs them from `build/apple/`, and times runs with `python3`
  instead of `date +%s%N`, which BSD `date` lacks. On macOS the baseline root
  defaults to the host-local `build/perf/baselines/macos-<arch>`, since the
  committed baselines are Linux host recordings. The perf scripts use
  `datetime.timezone.utc`, so they also run on Python 3.9 (macOS's system
  `python3`) (GitHub issue 147).

- The integration and durable-jobs suites run on macOS as Apple XCTest
  bundles. `tools/build_apple_xctest.sh --suite integration|durable-jobs` builds
  them and the binaries they launch (example servers, `eoc-smoke-render`,
  `durable-job-probe`). `arlen test --integration` runs the integration bundle
  and `arlen test`/`--all` runs unit then integration on macOS. `tools/ci/run_durable_jobs.sh`
  works on macOS. All 206 integration tests are discovered on Apple, and tests
  of GNUstep-only lanes skip there through the new `ALNSkipOnApple()`. Test
  helpers are portable: `ALNTestFrameworkBuildCommand()`,
  `ALNTestAppBinaryRelativePath()`, an Apple `ALNTestClientCompileCommand()`
  (new `tools/apple_compile_program.sh`), and child-process lookup through
  `ps -A` instead of GNU `ps --ppid`. Before, the lookup returned 0 on macOS
  and the test's `kill(0, SIGKILL)` killed the test runner. On macOS
  `arlen test --app` now prints the same per-class summary lines as the
  GNUstep runner (GitHub issue 153).

- Apple app builds (`tools/build_apple_app.sh`, used by `boomhauer` and
  `propane` on macOS) handle module templates like the GNUstep build. A module
  template overridden by the app (`templates/modules/<id>/...`) is no longer
  compiled twice, which failed the link with a duplicate
  `ALNEOCRender_modules_...` symbol. Override paths match exactly, including
  case, as on GNUstep, even on case-insensitive APFS. Only the outputs of the current templates
  are compiled, so a stale generated `.m` left under `.boomhauer/apple/gen/` is
  ignored (GitHub issue 152).

- `arlen deploy push`/`release` can package a release on macOS.
  `tools/deploy/build_release.sh` builds with `bin/build-apple` there and
  copies `.boomhauer/apple/boomhauer-app` and `build/apple/{arlen,boomhauer}`
  into the usual release layout, instead of failing in GNU `make`. The release
  scripts also run under macOS `/bin/bash` 3.2 and BSD tools:
  `build_release.sh` no longer aborts on empty `sharedPaths` or
  `prePackageCommands` arrays, `rollback_release.sh` no longer uses `mapfile`
  or `find -printf`, and `rollback_release.sh`/`smoke_release.sh` compare
  physical paths, so a release under a symlinked directory such as macOS
  `/var` is recognized as current. Running the service under launchd is
  covered in its own entry (GitHub issue 148).
- The notifications module has a `webpush` channel for browsers and installed
  web apps, including iOS 16.4+ home-screen apps (GitHub issue 173). Messages use
  RFC 8291 `aes128gcm` encryption, tested against the RFC's vectors, and
  RFC 8292 VAPID with 12-hour tokens reused per push service; requests carry
  `TTL`, `Urgency` and `Topic`. Definitions implement
  `notificationsModuleWebPushMessageForPayload:runtime:error:`; a `nudge`
  message sends no content. Messages over 3993 bytes, bad topics and unknown
  urgencies are rejected when queued. New user routes under
  `/notifications/api/push/` manage the signed-in user's subscriptions, and the
  module serves a service worker (with `Service-Worker-Allowed: /`) and a
  `window.ArlenWebPush` helper that asks for permission from a user gesture.
  Subscription endpoints must be on a known push-service host unless
  `webPush.allowedEndpointHosts` widens the list. `404`/`410` marks a
  subscription inactive; `429`, `5xx` and timeouts retry only the failed devices
  after `Retry-After`. The channel is off by default
  (`notificationsModule.webPush.enabled`, `ARLEN_WEBPUSH_*` environment
  variables), and `POST /notifications/api/push/test` is registered only with
  `webPush.testRoute.enabled`. `arlen webpush generate-keys` and
  `arlen webpush public-key` create and inspect VAPID keys.
- A jobs-module job can set `ALNJobsModuleRetryAfterSecondsErrorKey` in its
  failure's `userInfo` to delay its next attempt by at least that many seconds,
  past the `retryBackoff` cap, up to one day.

- `boomhauer --watch` on macOS now handles build failures the way the
  GNUstep path does. A failed build serves the diagnostic error page through
  the framework `boomhauer`, writes `.boomhauer/last_build_error.{log,meta}`,
  retries every `ARLEN_BOOMHAUER_BUILD_ERROR_RETRY_SECONDS`, and switches back
  to the app once a rebuild succeeds. Before, a broken first build exited watch
  mode, and a broken rebuild kept serving the old binary. `--prepare-only`
  failures also record `last_build_error.*` and print the log. The watcher now
  execs the server in its background job, so stopping `boomhauer` no longer
  leaves the app server running, and file changes are detected by fractional
  mtime and ctime (GitHub issue 151).
- `arlen build`, `check`, `test`, `routes` and `test --app` work on macOS
  without GNU `make`. `build` runs `bin/build-apple --with-boomhauer`, `check`
  runs `tools/test_apple.sh`, `test`/`test --unit` run the Apple XCTest unit
  bundle, and `routes` runs `bin/boomhauer --print-routes`. `arlen test --app`
  builds the app's tests into `.boomhauer/apple/tests/AppTests.xctest` with the
  new `tools/build_apple_app.sh --build-tests` and runs them with
  `xcrun xctest`. `build`/`check` JSON payloads add `toolchain`. `arlen perf`
  and `arlen test --integration` exit `2` on macOS with a GNUstep-only message
  instead of failing inside `make` (GitHub issue 146).
- `propane` and `jobs-worker` run on macOS. They build with the Apple
  toolchain instead of `make` and run the app from
  `.boomhauer/apple/boomhauer-app`, and `propane`'s FD-pressure checks use
  `lsof` where `/proc` is missing. `propane`, `jobs-worker` and `arlen doctor`
  no longer use bash 4 syntax that macOS `/bin/bash` 3.2 rejects: `${var,,}`,
  a heredoc inside `< <(...)`, and expanding empty arrays under `set -u`.
  Before, `propane` aborted at startup on macOS. `ShellPortabilityTests` guards the scripts that run on
  macOS against those constructs (GitHub issue 144).

- Apple builds are incremental. `tools/build_apple.sh`, `build_apple_app.sh`
  and `build_apple_xctest.sh` record clang depfiles and skip objects whose
  source and headers are unchanged, and skip archiving or linking when no input
  changed. Changing the compiler or flags clears the object cache. Generated
  templates are reused through the `eocc` manifest instead of being deleted on
  every run. A no-op `bin/build-apple` now takes under a second instead of
  ~20s, so each `arlen` command on macOS no longer pays for a full rebuild
  (GitHub issue 142).
- Named route parameters (`:id`) are percent-decoded. Arlen's generated
  TypeScript client and the OpenAPI explorer send parameters through
  `encodeURIComponent`, so an identifier such as `user:abc` arrived as
  `user%3Aabc` and its lookup failed with a 404. Values are decoded once after
  the path is split, so `%2F` stays inside the value. Decoding is
  all-or-nothing and the same on Apple and GNUstep: a segment with a malformed
  escape, an encoded NUL (`%00`), or bytes that are not strict UTF-8 is kept
  exactly as sent. Wildcard (`*name`) values are unchanged.
  **Upgrade note:** apps that decoded route parameters themselves should stop,
  or values containing `%25` decode twice (GitHub issue 154).

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

- PostgreSQL realtime fanout no longer crashes on macOS on its first publish.
  Its publish queue was not retained under ARC on Apple, where dispatch queues
  are Objective-C objects. Event-stream stores now serialize their
  `CREATE TABLE`/`CREATE INDEX` with an advisory lock, so stores or processes
  starting at the same time against a fresh database no longer fail with
  `pg_type_typname_nsp_index` (GitHub issue 138).

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

- `propane` and `jobs-worker` no longer run a stale app binary from a
  built source checkout. A built checkout also has `build/arlen`, so the
  launchers treated it as a packaged release and ran whatever
  `.boomhauer/build/boomhauer-app` an earlier build had left. That meant code
  changes did not take effect until boomhauer was rerun. Only a framework root
  without `GNUmakefile` and `src/Arlen` counts as a packaged release now;
  packaged releases from `arlen deploy push` still run their shipped binary
  (GitHub issue 150).

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
