# Release Notes

## Unreleased

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

- `ALNPg` now decodes `json`/`jsonb` values that hold a scalar document (a
  string, number, boolean or `null`) instead of failing the whole query
  (#182).

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
  sessions still hold a worker while open (#187).

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
  an unknown channel are rejected with `422` instead of being stored. How and
  when state is written is unchanged (#227). `notifications` moves to `1.1.2`.

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
