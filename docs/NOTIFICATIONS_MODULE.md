# Notifications Module

The first-party `notifications` module productizes durable email, in-app, webhook, and Web Push delivery on top of the `jobs` module, `ALNMailAdapter`, and the application webhook adapter.

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

Notification definitions may also implement:

- `notificationsModuleDefaultChannels`
- `notificationsModuleWebhookRequestForPayload:runtime:error:`
- `notificationsModuleWebPushMessageForPayload:runtime:error:` (see [Web Push](#web-push))

Configure provider classes and the optional preference hook in app config:

```plist
notificationsModule = {
  sender = "notifications@example.test";
  persistence = {
    enabled = YES;
    path = "var/module_state/notifications-development.plist";
  };
  providers = {
    classes = ( "MyAppNotificationsProvider" );
  };
  preferences = {
    hookClass = "MyAppNotificationPreferenceHook";
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

Runtime access is available through `ALNNotificationsModuleRuntime`.

## Delivery Model

- queueing a notification enqueues the system job `notifications.dispatch`
- the jobs module performs async delivery
- preview and test-send reuse the same notification definition contract as queued delivery
- current first-party delivery paths are:
  - email through `ALNMailAdapter`
  - in-app inbox entries with durable inbox/outbox/preference state
  - webhook delivery through the application webhook adapter
  - Web Push to subscribed browsers and home-screen web apps (see [Web Push](#web-push))
- notification metadata may provide `channelPolicies` per channel for queue, max-attempt, and retry-backoff routing
- explicit channel queueing records queued audit entries before worker delivery and can fan out into per-channel jobs
- in-app delivery publishes realtime fanout on `notifications.inbox.<recipient>`
- inbox entries are unread by default, persist read/unread state, and expose unread counts per recipient
- inbox entry metadata may include `href` or `path`; the HTML inbox renders that as a first-class deep link when it is an `http`/`https` URL or a same-origin relative path (`/settings`, `orders/7`). Other values (`javascript:`, `data:`, `ftp:`, protocol-relative `//host`, anything with a backslash or control character) render without a link. The JSON inbox returns the metadata unchanged, so API clients should apply the same check.
- the outbox and each recipient's inbox are capped; when a new entry would exceed the cap, the oldest entries are dropped (see [Retention limits](#retention-limits))

Requested channels are validated against the notification definition before queueing or previewing.

## Queueing over HTTP

`POST /notifications/api/queue` takes `notification`, `payload` and optional
`channels`. A signed-in user can queue notifications only for themselves:

- the module sets `payload.recipient` to the caller's auth subject, and
  `payload.email` to their auth module account email (or removes it when the
  module has no email for them)
- a payload that names anyone else is refused with `403` and
  `meta.error` = `queueing a notification for another recipient or email
  address requires the admin role and AAL2`. That covers a `recipient` or
  `recipientSubject` other than the caller, any `recipients` entry other than
  the caller, and an `email` other than their own
- callers with the `admin` role at AAL2 (the test-send policy) can queue for
  any recipient or address; their payload is passed through unchanged

The rest of the payload reaches your definition as the caller sent it, so
treat it as user input. In particular, do not take webhook URLs or
other delivery targets from it for notifications users can queue.

App code that calls `ALNNotificationsModuleRuntime`
(`queueNotificationIdentifier:...`) is not affected: it addresses whoever the
app chooses.

## Retention limits

The module keeps its outbox and inboxes in memory (and in the state file when
persistence is on), so both are capped. Adding an entry past the cap drops the
oldest entries. The caps also apply when a state file is loaded.

| Key | Default | Meaning |
| --- | --- | --- |
| `outbox.maxEntries` | `1000` | Outbox audit entries kept across all notifications. |
| `inbox.maxEntriesPerRecipient` | `200` | In-app entries kept per recipient. |

```plist
notificationsModule = {
  outbox = { maxEntries = 5000; };
  inbox = { maxEntriesPerRecipient = 500; };
};
```

Values must be positive integers; anything else uses the default.
`resolvedConfigSummary` reports the active caps as `maxOutboxEntries` and
`maxInboxEntriesPerRecipient`.

## Inbox pagination

`GET /notifications/api/inbox` and `GET /notifications/inbox` accept `limit`
and `offset` query parameters. Entries stay oldest-first. Without `limit` the
whole inbox is returned, as before (it is bounded by
`inbox.maxEntriesPerRecipient`); `limit` is clamped to 200. The JSON response
adds `pagination = { limit, offset, returned, total, hasMore }`;
`totalCount` and `unreadCount` still describe the whole inbox. The HTML inbox
shows previous/next page links when `limit` is set. Runtime callers can use
`-[ALNNotificationsModuleRuntime inboxSummaryForRecipient:limit:offset:]`.

## Preference validation

`POST /notifications/api/preferences`, `POST /notifications/preferences` and
`-updateNotificationPreferences:forRecipient:error:` reject preferences for a
notification identifier that is not registered, or for a channel that is
neither a first-party channel (`email`, `in_app`, `webhook`, `webpush`) nor
declared by a registered notification. The API answers `422`; the runtime
returns `ALNNotificationsModuleErrorValidationFailed` with `notification` (and
`channel`) in the error's `userInfo`. Stored preferences are left unchanged.

## Web Push

The `webpush` channel sends notifications to browsers and installed web apps
that are not open, including iOS 16.4+ home-screen web apps. Messages use RFC 8030
delivery, RFC 8291 `aes128gcm` encryption (the push service relays ciphertext
only), and RFC 8292 VAPID identification. The encryption is tested against the
RFC 8291 test vectors.

### Enable it

Web Push is off by default. Generate a VAPID key pair once per deployment and put
it in the server environment; the private key never belongs in the repository:

```bash
./build/arlen webpush generate-keys
# ARLEN_WEBPUSH_VAPID_PUBLIC_KEY=B...
# ARLEN_WEBPUSH_VAPID_PRIVATE_KEY=...
```

```plist
notificationsModule = {
  webPush = {
    enabled = YES;
    vapid = {
      subject = "mailto:ops@example.com";
    };
    nudge = {
      title = "Helpdesk";
      body = "Something needs your attention.";
      url = "/";
    };
  };
};
```

The environment overrides the plist: `ARLEN_WEBPUSH_ENABLED`,
`ARLEN_WEBPUSH_VAPID_PUBLIC_KEY`, `ARLEN_WEBPUSH_VAPID_PRIVATE_KEY` and
`ARLEN_WEBPUSH_VAPID_SUBJECT`. With Web Push enabled, the module refuses to
start when the keys are malformed or do not match, or when the subject is not a
`mailto:` or `https:` URL (Apple's push service requires a contact subject).
`arlen webpush public-key` prints the public key for the private key in the
environment.

Keep the key pair stable: browsers bind each subscription to the public key, so
a new pair invalidates every existing subscription. The client helper notices a
changed key and resubscribes the next time the user subscribes.

### Define a push message

Add `webpush` to a definition's channels and implement
`notificationsModuleWebPushMessageForPayload:runtime:error:`:

```objc
- (NSDictionary *)notificationsModuleWebPushMessageForPayload:(NSDictionary *)payload
                                                      runtime:(ALNNotificationsModuleRuntime *)runtime
                                                        error:(NSError **)error {
  return @{
    @"recipient" : payload[@"recipient"],
    @"title" : @"Your turn",
    @"body" : @"Ticket 42 is waiting for your confirmation.",
    @"url" : @"/tickets/42",
    @"tag" : @"ticket-42",
    @"topic" : @"ticket-42",
    @"urgency" : @"high",
    @"ttl" : @3600,
  };
}
```

| Key | Meaning |
| --- | --- |
| `title` | Required unless `nudge` is set. |
| `body`, `url`, `tag` | Shown by the service worker. `url` opens on click and must be on the app's origin; other origins open `/`. `tag` replaces an earlier notification with the same tag on the device. |
| `topic` | Up to 32 base64url characters. The push service keeps only the latest undelivered message per topic. |
| `urgency` | `very-low`, `low`, `normal` (default) or `high`. |
| `ttl` | Seconds the push service holds an undelivered message (default `webPush.ttlSeconds`, 1 day). |
| `nudge` | `YES` sends no content at all; the device shows `webPush.nudge` text. Use it when notification text must not leave the server. |
| `recipient` / `recipients` | Auth subjects to notify; defaults to the payload's `recipient`. |

The encoded message must fit in 3993 bytes, the limit for a single 4096-byte
encrypted record. Larger messages, invalid topics and unknown urgencies are
rejected when the notification is queued or previewed, never truncated.

iOS has no silent push: every push displays a notification. The service worker
always shows one, falling back to the `nudge` text for content-free or unreadable
messages.

### Subscribe a device

Load the client helper and call `ArlenWebPush.subscribe()` from a click or tap
handler. iOS only grants notification permission in response to a user gesture,
and only to web apps installed on the home screen, so the app needs a web app
manifest and the user must add it to the home screen first.

```html
<meta name="csrf-token" content="<%= $csrfToken %>">
<script src="/notifications/push/client.js"
        data-api-prefix="/notifications/api"
        data-service-worker="/notifications/push/service-worker.js"
        data-scope="/"></script>
<button id="enable-push">Turn on notifications</button>
<script>
  document.getElementById('enable-push').addEventListener('click', function () {
    ArlenWebPush.subscribe().then(function () { /* subscribed */ },
                                  function (error) { console.warn(error.message); });
  });
</script>
```

Pass `csrfToken` into the template context from the controller
(`-[ALNController csrfToken]`). The helper sends it from the `csrf-token` meta tag
(or a `data-csrf-token` attribute) in the `X-CSRF-Token` header; set
`data-csrf-header` if the app changed `csrf.headerName`. `ArlenWebPush` also
provides `status()`, `unsubscribe()`, `listSubscriptions()` and `sendTest()`.

The service worker is served from `/notifications/push/service-worker.js` with
`Service-Worker-Allowed: /`, so it can control the whole app (`scope: "/"`). It
shows the title, body and tag, opens `url` on click, and focuses an already open
window for that URL.

### Subscriptions

Subscriptions belong to the signed-in user (the auth subject); the routes ignore
any recipient in the request body. Each subscription records its endpoint, keys,
user agent, creation time and last successful delivery.

- Endpoints must be `https` on a known push service: `push.apple.com`,
  `fcm.googleapis.com`, `push.services.mozilla.com` or `notify.windows.com`, and
  their subdomains. Browsers supply the endpoint, so this list keeps the server
  from posting to arbitrary hosts. Widen it with `webPush.allowedEndpointHosts`
  (`"*"` allows any https host).
- A device's endpoint is unique: subscribing it again refreshes it, and
  subscribing it under another user moves it to that user.
- Each user keeps at most `webPush.maxSubscriptionsPerRecipient` subscriptions
  (default 10); the oldest are dropped.
- When a push service answers `404` or `410`, the subscription is marked inactive
  with a reason and time instead of being deleted, so the app can show "this
  device stopped receiving notifications". Subscribing again reactivates it.

Subscriptions are stored in `var/module_state/notifications-<environment>-webpush.plist`
beside the module state file (override with `webPush.subscriptions.path`), and in
memory in the `test` environment. Every read and write re-reads the file under an
advisory lock, so the app server and `arlen jobs worker` on the same host share
one view. Run them on one host, or point both at shared storage that supports
`flock`.

### Delivery and retries

Each queued `webpush` job sends one encrypted `POST` per active subscription of
each recipient, with `TTL`, `Urgency`, `Topic`, `Content-Encoding: aes128gcm` and
a VAPID `Authorization` header. VAPID tokens expire after 12 hours and are reused
per push service.

- `2xx`: delivered; the subscription's last-success time is updated.
- `404`/`410`: the subscription is marked inactive.
- `429`, `5xx` or no response: only the failed devices are retried, in a new
  `webpush` job, after the push service's `Retry-After` or the channel's retry
  backoff, whichever is longer. Devices that already received the message are
  not notified again. That retry job then follows the channel's `maxAttempts` and
  `retryBackoff` policy and never retries sooner than a `Retry-After`.
- Any other status fails that device and is recorded in the outbox.

The channel respects `ALNNotificationPreferenceHook` and per-user preferences
(`webpush` channel key), like the other channels. With Web Push disabled, queued
`webpush` deliveries are recorded as `suppressed`.

### Send a test

`-[ALNNotificationsModuleRuntime sendWebPushTestToRecipient:error:]` sends a fixed
test message to a user's devices, bypassing definitions, preferences and the
queue. Set `webPush.testRoute.enabled = YES` to also expose it to signed-in users
as `POST /notifications/api/push/test` for their own devices; the route is off by
default.

### Web Push configuration

| Key | Default | Meaning |
| --- | --- | --- |
| `webPush.enabled` | `NO` | Master switch per environment (`ARLEN_WEBPUSH_ENABLED`). |
| `webPush.vapid.publicKey` / `privateKey` | empty | Prefer `ARLEN_WEBPUSH_VAPID_PUBLIC_KEY` / `ARLEN_WEBPUSH_VAPID_PRIVATE_KEY`. |
| `webPush.vapid.subject` | empty | `mailto:` or `https:` contact (`ARLEN_WEBPUSH_VAPID_SUBJECT`). |
| `webPush.ttlSeconds` | `86400` | Default TTL, capped at 28 days. |
| `webPush.urgency` | `normal` | Default urgency. |
| `webPush.allowedEndpointHosts` | push services above | Hosts subscriptions may use. |
| `webPush.maxSubscriptionsPerRecipient` | `10` | Devices kept per user (1-100). |
| `webPush.nudge.title` / `body` / `url` / `icon` / `badge` | `New notification` / `Open the app to see it.` / `/` | Text the service worker shows for content-free pushes. |
| `webPush.testRoute.enabled` | `NO` | Registers `POST /notifications/api/push/test`. |
| `webPush.subscriptions.path` | beside the state file | Subscription store; relative paths resolve against the app root. |
| `webPush.transportClass` | libcurl transport | Class conforming to `ALNWebPushTransport`, for tests or custom egress. |

## Surfaces

HTML routes:

- `GET /notifications/`
- `GET /notifications/inbox`
- `POST /notifications/inbox/read-all`
- `POST /notifications/inbox/:entryID/read`
- `POST /notifications/inbox/:entryID/unread`
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
- `POST /notifications/api/inbox/read-all`
- `POST /notifications/api/inbox/:entryID/read`
- `POST /notifications/api/inbox/:entryID/unread`
- `POST /notifications/api/queue`
- `POST /notifications/api/preview`
- `POST /notifications/api/test-send`
- `GET /notifications/api/preferences`
- `POST /notifications/api/preferences`
- `GET /notifications/api/push/config`
- `GET /notifications/api/push/subscriptions`
- `POST /notifications/api/push/subscriptions`
- `POST /notifications/api/push/unsubscribe`
- `POST /notifications/api/push/test` (only with `webPush.testRoute.enabled`)

Scripts (no session required; they contain no user data):

- `GET /notifications/push/service-worker.js`
- `GET /notifications/push/client.js`

The notifications API is included in module OpenAPI output.

## Protection

- inbox and preferences surfaces require an authenticated user context
- outbox, preview, and test-send surfaces require the shared admin policy:
  - authenticated session
  - `admin` role
  - AAL2 step-up

That same split applies to the JSON routes: definitions, inbox, inbox read-state mutations, queueing, preferences, and the `push/*` routes require AAL1; outbox, preview, and test-send require `admin` plus AAL2. Queueing at AAL1 is limited to the signed-in user's own notifications; queueing for anyone else requires `admin` plus AAL2 (see [Queueing over HTTP](#queueing-over-http)). Push subscription routes act only on the signed-in user's own subscriptions, and their `POST` requests go through the app's CSRF policy.

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
- persistence: enabled outside `test`, with an auto-resolved module state path when no explicit path is provided
- Web Push: disabled
- `outbox.maxEntries`: `1000`; `inbox.maxEntriesPerRecipient`: `200`

## Current Limits

- first-party channels stop at email, in-app, webhook, and Web Push; SMS/chat vendor integrations remain future add-ons
- Web Push sends one encrypted record per message (at most 3993 bytes of message JSON); Safari's Declarative Web Push format is not supported yet
- the Web Push subscription store is a locked file, shared by processes on one host
- preview/test-send are first-party module flows, not a generalized template authoring UI
