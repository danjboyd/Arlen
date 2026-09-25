# Release Notes

## Upcoming Release Candidate

- Modules: relative jobs, storage, notifications and search persistence paths,
  including the `var/module_state/...` defaults, now resolve against the
  application root instead of the process working directory.
  `arlen jobs worker` runs from the framework root, so it had been reading and
  writing scheduler state under the framework checkout, separately from the
  server. Adds `-[ALNApplication appRootPath]` and `-pathRelativeToAppRoot:`
  (GitHub issue 76).

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
