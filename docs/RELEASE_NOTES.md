# Release Notes

## Upcoming Release Candidate

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
