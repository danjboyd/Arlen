# Notifications Module

The first-party `notifications` module builds on the `jobs` module and `ALNMailAdapter` to provide a deterministic notification foundation.

## Install

```bash
./build/arlen module add jobs
./build/arlen module add notifications
./build/arlen module doctor --json
./build/arlen module migrate --env development
```

The module is vendored into `modules/notifications/` and depends on `jobs`.

## App Registration

Apps register notifications explicitly through Objective-C provider classes.

- `ALNNotificationDefinition`: one notification contract
- `ALNNotificationProvider`: supplies notification definitions to the runtime

Configure provider classes in app config:

```plist
notificationsModule = {
  providers = {
    classes = ( "MyAppNotificationsProvider" );
  };
};
```

Runtime access is available through `ALNNotificationsModuleRuntime`.

## Delivery Model

- queueing a notification enqueues the system job `notifications.dispatch`
- the jobs module performs async delivery
- current first-party delivery paths are:
  - email through `ALNMailAdapter`
  - in-app inbox entries stored in the runtime snapshot

Requested channels are validated against the notification definition before queueing.

## JSON Surface

- `GET /notifications/api/definitions`
- `GET /notifications/api/outbox`
- `GET /notifications/api/inbox/:recipient`
- `POST /notifications/api/queue`

The notifications API is included in module OpenAPI output.

## Defaults

Manifest defaults:

- prefix: `/notifications`
- API prefix: `/notifications/api`
- sender: `notifications@example.test`

## Current Limits

- The 14C slice is JSON-first; HTML inbox, preview, test-send, and preferences surfaces are planned for 14D.
- Outbox and inbox state are runtime-managed in this slice rather than backed by dedicated module tables.
- Realtime inbox fanout is not wired yet; the module is structured so it can layer on later without changing the core notification-definition contract.
