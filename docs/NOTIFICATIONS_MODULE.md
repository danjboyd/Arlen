# Notifications Module

The first-party `notifications` module productizes email and in-app delivery on top of the `jobs` module and `ALNMailAdapter`.

## Install

```bash
./build/arlen module add jobs
./build/arlen module add notifications
./build/arlen module doctor --json
./build/arlen module migrate --env development
```

Install `admin-ui` as well if you want the notification resources to appear in the shared admin surface.

## App Registration

Apps register notifications explicitly through Objective-C provider classes.

- `ALNNotificationDefinition`: one notification contract
- `ALNNotificationProvider`: supplies notification definitions to the runtime
- `ALNNotificationPreferenceHook`: optional policy hook for per-recipient channel enablement decisions

Configure provider classes and the optional preference hook in app config:

```plist
notificationsModule = {
  sender = "notifications@example.test";
  providers = {
    classes = ( "MyAppNotificationsProvider" );
  };
  preferences = {
    hookClass = "MyAppNotificationPreferenceHook";
  };
};
```

Runtime access is available through `ALNNotificationsModuleRuntime`.

## Delivery Model

- queueing a notification enqueues the system job `notifications.dispatch`
- the jobs module performs async delivery
- preview and test-send reuse the same notification definition contract as queued delivery
- current first-party delivery paths are:
  - email through `ALNMailAdapter`
  - in-app inbox entries stored in the runtime snapshot

Requested channels are validated against the notification definition before queueing or previewing.

## Surfaces

HTML routes:

- `GET /notifications/`
- `GET /notifications/inbox`
- `GET /notifications/preferences`
- `POST /notifications/preferences`
- `GET /notifications/outbox`
- `GET /notifications/preview`
- `POST /notifications/test-send`

JSON routes:

- `GET /notifications/api/definitions`
- `GET /notifications/api/outbox`
- `GET /notifications/api/outbox/:entryID`
- `GET /notifications/api/inbox`
- `GET /notifications/api/inbox/:recipient`
- `POST /notifications/api/queue`
- `POST /notifications/api/preview`
- `POST /notifications/api/test-send`
- `GET /notifications/api/preferences`
- `POST /notifications/api/preferences`

The notifications API is included in module OpenAPI output.

## Protection

- inbox and preferences surfaces require an authenticated user context
- outbox, preview, and test-send surfaces require the shared admin policy:
  - authenticated session
  - `admin` role
  - AAL2 step-up

That same split applies to the JSON routes: definitions, inbox, queueing, and preferences require AAL1; outbox, preview, and test-send require `admin` plus AAL2.

## Admin UI Integration

When `admin-ui` is installed, the module contributes shared admin resources for:

- notification outbox history
- notification-definition inspection with preview links

The default resource provider is wired through `notificationsModule.adminUI.resourceProviderClass`.

## Defaults

Manifest defaults:

- prefix: `/notifications`
- API prefix: `/notifications/api`
- sender: `notifications@example.test`
- preference hook class: empty

## Current Limits

- outbox, inbox, and preference state are runtime-managed rather than backed by dedicated module tables
- realtime inbox fanout is not wired yet
- preview/test-send are first-party module flows, not a generalized template authoring UI
