# Storage Module

The first-party `storage` module productizes collection registration, direct uploads, signed downloads, persistent object catalogs, and transform-backed variant processing on top of `ALNAttachmentAdapter` and the `jobs` module.

## Install

```bash
./build/arlen module add jobs
./build/arlen module add storage
./build/arlen module doctor --json
./build/arlen module migrate --env development
```

Install `admin-ui` as well if you want storage objects to appear in the shared admin surface.

## App Registration

Apps register storage collections explicitly through Objective-C provider classes.

- `ALNStorageCollectionDefinition`: one collection contract
- `ALNStorageCollectionProvider`: supplies collection definitions to the runtime

Configure provider classes in app config:

```plist
storageModule = {
  persistence = {
    enabled = YES;
    path = "var/module_state/storage-development.plist";
  };
  cleanup = {
    intervalSeconds = 300;
  };
  collections = {
    classes = ( "MyAppStorageCollectionProvider" );
  };
};
```

Relative `persistence.path` values, and the default
`var/module_state/<module>-<environment>.plist`, resolve against the
application root (`-[ALNApplication appRootPath]`: config `appRoot`, then
`ARLEN_APP_ROOT`) rather than the process working directory. The HTTP server,
`arlen jobs worker` and other CLI delegates therefore share one state file.
Production deployments should still use absolute paths under the release's
`shared/` directory.

The default `persistence.backend = sqlite` stores the catalog at
`<persistence.path>.sqlite3`. Each object, upload session, and collection
membership has its own row. A change serializes and writes only changed rows,
inside a SQLite transaction with full synchronous durability. Catalog snapshots
remain cached in memory; refreshing another worker's changed catalog reads all
rows, so refresh memory/CPU still scale with catalog size.

On first startup, a transaction imports an existing XML or binary plist at
`persistence.path`. Concurrent starters import it only once. An interrupted or
failed import rolls back and can be retried. The original file is retained as a
migration backup and is no longer read after import. Stop all old workers and
jobs processes before upgrading; do not run plist and SQLite workers together.
Back up the SQLite database with SQLite's backup facility, or stop every writer
before copying it and any journal. Do not restore only the obsolete plist.

`persistence.backend = plist` explicitly retains the legacy whole-file XML
format for unmigrated installations. There is no automatic fallback when SQLite
is unavailable, and switching a migrated path back to plist is refused.

Storage module 1.4.4 avoids unnecessary normalization copies when a GNUstep
legacy plist catalog already has valid values and trimmed, nonempty string keys.
Catalogs needing metadata conversions retain the existing normalization path.
XML output, private atomic writes, older binary reads, and the Apple serializer's
container copying are unchanged.
Streamed downloads also recognize legacy checksums stored only in
`analysis.checksumSHA256`, matching buffered downloads. This works with explicit
plist catalogs and imported SQLite catalogs without backfilling stored records.
Size and checksum verification still reject changed or corrupted attachments.
Upgrade a vendored storage module with `arlen module upgrade storage`.

Storage module 1.4.3 creates each Windows legacy plist temporary file exclusively
with a protected DACL granting access only to the current process token user,
before writing catalog bytes. The handle is not inherited by child processes.
A same-directory atomic replacement carries that private DACL to the catalog;
failed writes retain the previous catalog and remove their temporary file.
The parent directory ACL is unchanged. POSIX retains owner-only `0600` creation
independently of the process umask. Keep the parent private for catalog integrity
and availability as well as protecting backup files from older versions.
A private file DACL does not prevent catalog pathname replacement by an actor
allowed to delete or replace entries in the parent directory.

Processes sharing a catalog must run on one host and use a local filesystem:

- Changes take `<persistence.path>.lock` (`flock` on POSIX, `LockFileEx` on
  Windows), refresh the catalog, then commit a SQLite transaction. This keeps
  application-level read-modify-write operations coherent across workers.
- Reads detect changed database files and refresh one consistent SQLite
  snapshot. They do not take the cross-process application lock. If a writer
  is busy, readers retain the last complete cached snapshot unless a previous
  reload or write failed. SQLite reads have a short 100 ms busy timeout.
- A corrupt or unreadable catalog blocks cached object reads, download-token
  issuance, and both buffered and streamed downloads, even when the caller
  omits `NSError`. APIs without an error result return an empty list or summary.
  Repair the catalog before retrying; successful reload restores service.
- Backend exceptions release the process and shared writer locks. The next
  operation reloads persisted state instead of retaining uncommitted entries;
  failed object updates also remove their newly written attachment.
- Object and upload-session IDs are random; tokens bind to each object's nonce.
  Attachment creation and hashing happen outside the catalog lock.
- `persistence.lockTimeoutSeconds` defaults to 10; exhausted lock/SQLite busy
  waits return `ALNStorageModuleErrorStateBusy` (HTTP 503, `Retry-After: 1`).
  Startup cleanup allows `startupLockTimeoutSeconds` (default 60), then warns
  and skips cleanup if busy. First-time SQLite setup allows 10 seconds.
- POSIX databases are owner-only (`0600`). Windows uses the current-user
  protected DACL. Keep the parent directory private too.

The storage backend requires the OS SQLite runtime: Linux `libsqlite3.so.0`
(Debian/Ubuntu package `libsqlite3-0`), macOS `libsqlite3.dylib`, or Windows
`winsqlite3.dll`. It loads the stable C ABI without SQLite development headers
or import libraries. Missing libraries cause an explicit module startup error.

Attachment data has to be shared the same way, because the catalog names
attachments by ID:

- With persistence on and no attachment adapter configured, the module
  replaces the application's in-memory default with a filesystem adapter at
  `<state file without extension>-attachments/` (or `storageModule.attachments.path`,
  relative to the app root).
- With persistence on, an attachment adapter that keeps data in process memory
  (`ALNInMemoryAttachmentAdapter`, alone or wrapped) is refused at startup.
  Configure a filesystem or object-store adapter, or turn persistence off.
- Downloads and variant jobs check the attachment's size and SHA-256 against
  the object record, and answer 404 rather than serve bytes that don't match.
  A delete removes only attachments whose bytes match the record.

With persistence off, each process keeps its own catalog. That suits one
process, but with `propaneAccessories.workerCount > 1` most downloads and
jobs-worker variants would miss their objects, so startup logs a
`storage_unshared_state` warning outside `test` and `development`, `propane`
prints a warning, and `arlen module doctor` reports it.

Filesystem-backed signed downloads retain an opened regular file after checking
its size and SHA-256 in 64 KiB chunks. HTTP transmission uses that same descriptor,
with HEAD, single byte ranges, and checksum ETags; it does not materialize the
whole attachment. Path replacement after verification cannot substitute another
object. Framework attachment writes use new IDs and atomic replacement; files
must remain immutable during delivery. This does not protect against privileged
local writers modifying an already-open file in place. Truncation causes a short
transfer and connection closure.

Custom adapters can implement `openAttachmentFileForID:metadata:error:` to opt
into this path. NSData-only adapters retain their existing materializing download
behavior. Variant hooks still accept NSData: `storageModule.maxVariantInputBytes`
defaults to 16 MiB (zero restores the default), rejecting larger source records
before reading them. File-backed reads are bounded to the limit plus one byte;
NSData-only adapters must enforce their own read allocation bound. Trusted variant
hooks remain responsible for the memory used to construct output data.

Runtime access is available through `ALNStorageModuleRuntime`.

## Collection Metadata

Each collection definition supplies metadata such as:

- `title`
- `description`
- `acceptedContentTypes`
- `maxBytes`
- `visibility` (`public` or `private`)
- `retentionDays`
- `variants`

`acceptedContentTypes` entries are exact types (`image/png`) or wildcards
(`image/*`, `*/*`). A collection without `acceptedContentTypes` accepts
`*/*`. Wildcards never match `text/html`, `image/svg+xml` or
`application/xhtml+xml`; a collection that should store those must list them
exactly.

Definitions may also implement the optional validation hook `storageModuleValidateObjectNamed:contentType:sizeBytes:metadata:runtime:error:` for app-specific policy checks.
Definitions may implement `storageModuleVariantRepresentationForObject:variantDefinition:originalData:originalMetadata:runtime:error:` to generate first-party transformed variants rather than copy-only derivatives.

## Surfaces

HTML routes:

- `GET /storage/`
- `GET /storage/collections/:collection`
- `GET /storage/collections/:collection/objects/:objectID`
- `POST /storage/collections/:collection/objects/:objectID/delete`
- `POST /storage/collections/:collection/objects/:objectID/regenerate-variants`

JSON routes:

- `GET /storage/api/collections`
- `GET /storage/api/collections/:collection/objects`
- `GET /storage/api/collections/:collection/objects/:objectID`
- `POST /storage/api/upload-sessions`
- `POST /storage/api/upload-sessions/:sessionID/upload`
- `POST /storage/api/collections/:collection/objects/:objectID/download-token`
- `GET /storage/api/download/:token`
- `POST /storage/api/collections/:collection/objects/:objectID/delete`
- `POST /storage/api/collections/:collection/objects/:objectID/regenerate-variants`

The management JSON routes are included in module OpenAPI output.

## Protection

- the HTML management surface requires the shared admin policy:
  - authenticated session
  - `admin` role
  - AAL2 step-up
- the JSON management and upload routes use the same admin+AAL2 protection
- `GET /storage/api/download/:token` is token-based and does not require a session

## Upload and Download Flow

- `POST /storage/api/upload-sessions` validates collection policy and issues a signed upload token
- `POST /storage/api/upload-sessions/:sessionID/upload` persists the object through the configured attachment adapter and durable module state
- `POST /storage/api/collections/:collection/objects/:objectID/download-token` issues a signed download token
- `GET /storage/api/download/:token` streams the stored object if the token is valid and unexpired

### Download Headers

The download response uses the content type recorded at upload, which the
uploader declared; the bytes are not checked against it. The declared type
must be exactly one media type (`type/subtype` with optional token
parameters); lists, quoted strings and control characters are rejected at
upload. It is stored normalized (lowercase `type/subtype`, plus a `charset`
parameter if one was given), and the download sends only that normalized
type. To keep stored files from running as pages on the app's origin, the
download sets:

- `Content-Disposition: attachment; filename="..."` by default. The quoted
  filename is the object name reduced to ASCII letters, digits and `._-`, with
  the original name in `filename*` when it differs.
- `Content-Disposition: inline` only for `image/png`, `image/jpeg`,
  `image/gif`, `image/webp`, `image/avif`, `application/pdf`, `audio/*` and
  `video/*`. HTML, SVG, XML, JavaScript and every other type download as
  attachments.
- `Content-Security-Policy: sandbox` on every download except inline PDF
  (browser PDF viewers do not run in a sandboxed document; PDF keeps the app's
  normal policy).
- `X-Content-Type-Options: nosniff`.

Config knobs:

- `storageModule.uploadSessionTTLSeconds`
- `storageModule.downloadTokenTTLSeconds`
- `storageModule.cleanup.intervalSeconds`
- `storageModule.signingSecret`

### Signing Secret

Upload and download tokens are HMAC-SHA256 signed with
`storageModule.signingSecret`. Arlen does not ship a default key.

- Set the secret with `ARLEN_STORAGE_SIGNING_SECRET` in the process
  environment, or `storageModule.signingSecret` in untracked config. The
  environment value wins.
- The secret must be at least 32 characters in every environment. Generate
  one with `openssl rand -hex 32`.
- Outside `development` and `test`, placeholder and published example values
  are refused (`reason = placeholder_secret` or `published_example_secret`);
  see [Signing secrets](CONFIGURATION_REFERENCE.md#signing-secrets).
- Outside `development` and `test`, the module refuses to configure when no
  secret is set (`ALNStorageModuleErrorInvalidConfiguration`,
  `config_key = storageModule.signingSecret`).
- In `development` and `test`, an unset secret uses a random per-process key
  and logs a warning. Tokens issued before a restart then stop validating.
- Use a secret distinct from `session.secret`. Rotating it invalidates
  outstanding upload and download tokens.

## Variants

- collection metadata can declare variant definitions
- storing an object with variants marks the object `variantState = pending`
- the module queues `storage.generate_variant` jobs through the shared jobs runtime
- failed variant jobs mark the variant and object state as `failed` with persisted error metadata
- admin HTML, admin JSON, and shared `admin-ui` actions can trigger variant regeneration

## Lifecycle And Adapter Capabilities

- the module registers the maintenance job `storage.cleanup`
- the default schedule `storage.cleanup.default` runs on the `maintenance` queue
- object deletion, upload-session expiry, variant success/failure, and maintenance runs are recorded in the module activity log
- dashboard/config summaries expose attachment adapter capability metadata for:
  - `temporaryDownloadURL`
  - `readOnly`
  - `scoped`
  - `mirroring`

## Admin UI Integration

When `admin-ui` is installed, the module contributes the `storage_objects` resource with:

- list and detail views for object metadata
- download-token path visibility
- `delete` and `regenerate_variants` actions

The default resource provider is wired through `storageModule.adminUI.resourceProviderClass`.

## Defaults

Manifest defaults:

- prefix: `/storage`
- API prefix: `/storage/api`
- upload session TTL: `900` seconds
- download token TTL: `300` seconds
- cleanup interval: `300` seconds
- signing secret: `storage-module-signing-secret`
- persistence: enabled outside `test`, with an auto-resolved module state path when no explicit path is provided

## Current Limits

- first-party analysis metadata is deterministic but lightweight; dimensions depend on available object metadata and the configured transform hook rather than a built-in media analyzer stack
- first-party preview/variant support is image-first; PDF/video-specific representation hooks remain future work
- collection filtering is simple search over collection, name, type, and object identifier
