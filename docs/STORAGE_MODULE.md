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

Config knobs:

- `storageModule.uploadSessionTTLSeconds`
- `storageModule.downloadTokenTTLSeconds`
- `storageModule.cleanup.intervalSeconds`
- `storageModule.signingSecret`

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
