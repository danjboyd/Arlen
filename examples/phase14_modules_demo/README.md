# Phase 14 Modules Demo

This sample app demonstrates the full Phase 14 module stack working together:

- `auth`
- `admin-ui`
- `jobs`
- `notifications`
- `storage`
- `ops`
- `search`

## Bootstrap

Set a real PostgreSQL DSN in `config/app.plist` by replacing `__ARLEN_PG_DSN__`,
then vendor the first-party modules into the app root:

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
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./bin/boomhauer --no-watch --port 4120
```

## What It Shows

- `/auth/...` and `/auth/api/...` provide the shared authentication and step-up flow.
- `/admin/...` and `/admin/api/...` expose app-owned resources plus module-contributed resources.
- `/jobs/...` and `/jobs/api/...` drive manual enqueue, scheduler, and worker execution.
- `/notifications/...` and `/notifications/api/...` provide preview and test-send flows on top of jobs + mail.
- `/storage/...` and `/storage/api/...` provide direct uploads, signed downloads, and variant processing.
- `/ops/...` and `/ops/api/...` summarize jobs, notifications, storage, health signals, metrics, and OpenAPI data.
- `/search/...` and `/search/api/...` query and reindex the app-owned `orders` admin resource.

## App-Owned Registration

`app_lite.m` keeps the app-owned surface intentionally small:

- `Phase14DemoOrdersProvider` contributes an `orders` admin resource
- `Phase14DemoJobProvider` and `Phase14DemoScheduleProvider` register jobs + schedules
- `Phase14DemoNotificationsProvider` registers one notification definition
- `Phase14DemoStorageCollectionProvider` registers one media collection

The first-party modules own the routes, templates, assets, JSON formatting, and
operator/admin policy around those app registrations.
