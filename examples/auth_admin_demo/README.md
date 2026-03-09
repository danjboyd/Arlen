# Auth + Admin Demo

This sample app demonstrates the full Phase 13 product layer:

- first-party `auth` installation
- first-party `admin-ui` installation
- app-owned admin resource registration via Objective-C protocols
- shared HTML and JSON contracts

## Bootstrap

Set a real PostgreSQL DSN in `config/app.plist` by replacing `__ARLEN_PG_DSN__`,
then vendor the first-party modules into the app root:

```bash
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add auth --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add admin-ui --json
./build/arlen module migrate --env development --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./bin/boomhauer --no-watch --port 4110
```

## What It Shows

- `/auth/...` provides the default HTML account flows.
- `/auth/api/...` provides the same auth contract as JSON for SPA clients.
- `/admin/...` provides the default EOC-rendered admin.
- `/admin/api/...` exposes the same admin resources as JSON.
- `app_lite.m` registers `AuthAdminDemoOrdersProvider`, which adds an app-owned
  `orders` resource into the shared admin resource registry.

## Custom Resource

`AuthAdminDemoOrdersResource` is intentionally simple. It demonstrates the
minimal Objective-C surface an app owns:

- metadata
- list/detail/update handlers
- custom action handler

The admin module handles routing, templates, policy defaults, OpenAPI exposure,
and JSON formatting around that resource.
