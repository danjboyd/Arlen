# Multi-Module Demo

This sample app demonstrates the matured multi-module stack working
together:

- `auth`
- `admin-ui`
- `jobs`
- `notifications`
- `storage`
- `ops`
- `search`

Compared with the initial multi-module demo, this app emphasizes the matured seams:

- richer admin resource metadata with filters, sorts, bulk actions, exports,
  and autocomplete
- search incremental sync, generation history, and drilldown-friendly resource
  metadata
- ops cards plus contributed widgets
- explicit durable module state paths for jobs, notifications, storage, search,
  and ops

## Bootstrap

Set a real PostgreSQL DSN in `config/app.plist` by replacing
`__ARLEN_PG_DSN__`, then vendor the first-party modules into the app root:

```bash
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add auth --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add admin-ui --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add jobs --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add notifications --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add storage --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add ops --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add search --json
./build/arlen module doctor --json
./build/arlen module migrate --env development --json
./build/arlen module assets --output-dir build/module_assets --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./bin/boomhauer --no-watch --port 4160
```

## What It Shows

- `/admin/...` and `/admin/api/...` expose an app-owned `orders` resource with
  typed filters, stable sorts, exports, bulk actions, and autocomplete.
- `/search/...` and `/search/api/...` reindex and query the same `orders`
  resource through the shared search contract.
- `/ops/...` and `/ops/api/...` expose history, drilldowns, and contributed
  widgets alongside the shared module summaries.
- `/jobs/...`, `/notifications/...`, and `/storage/...` exercise the matured
  durable module state paths and shared operator/admin protection.

## App-Owned Registration

`app_lite.m` intentionally keeps the app-specific code small:

- `Phase16DemoOrdersProvider` contributes one richer admin resource
- `Phase16DemoJobProvider` and `Phase16DemoScheduleProvider` register one job
  plus one maintenance schedule
- `Phase16DemoNotificationsProvider` registers one notification definition
- `Phase16DemoStorageCollectionProvider` registers one media collection
- `Phase16DemoOpsCardProvider` contributes one card and one widget

The first-party modules continue to own the routes, templates, JSON envelopes,
and operator/admin policy around those registrations.
