# Live UI Guide

Arlen's Phase 25 live UI layer is fragment-first. It does not try to be a
full-state diff engine.

Current scope:

- HTML-over-the-wire live responses
- live links and live forms
- explicit fragment replace/update/append/prepend/remove operations
- websocket-backed push updates
- live navigation redirects

Current non-goals:

- whole-page/stateful diffing
- implicit component lifecycle/state stores
- client-side virtual DOM

## 1. Runtime Asset

Arlen serves a built-in browser runtime at:

- `/arlen/live.js`

Load it in your layout:

```html
<script src="/arlen/live.js" defer></script>
```

## 2. Live Response Protocol

Live responses use:

- `Content-Type: application/vnd.arlen.live+json; charset=utf-8`
- `X-Arlen-Live-Protocol: arlen-live-v1`

Payload shape:

```json
{
  "version": "arlen-live-v1",
  "operations": [
    { "op": "update", "target": "#orders", "html": "<li>Alpha</li>" }
  ],
  "meta": {
    "request_id": "req-123",
    "route": "orders.index"
  }
}
```

Supported operations today:

- `replace`
- `update`
- `append`
- `prepend`
- `remove`
- `navigate`
- `dispatch`

## 3. Authoring Live Links and Forms

Mark links or forms with `data-arlen-live` so the runtime intercepts them.

Optional authoring attributes:

- `data-arlen-live-target`: CSS selector to patch
- `data-arlen-live-swap`: `replace`, `update`, `append`, or `prepend`
- `data-arlen-live-component`: stable component identifier for the request
- `data-arlen-live-event`: event name describing the user action

Example form:

```html
<form
  method="post"
  action="/orders/filter"
  data-arlen-live
  data-arlen-live-target="#orders-table"
  data-arlen-live-swap="update"
  data-arlen-live-component="orders-table"
  data-arlen-live-event="filter">
  <input type="hidden" name="csrf_token" value="<%= $csrf_token %>">
  <input type="search" name="query" value="<%= $query %>">
  <button type="submit">Filter</button>
</form>
```

Example link:

```html
<a
  href="/orders/page/2"
  data-arlen-live
  data-arlen-live-target="#orders-table"
  data-arlen-live-swap="update"
  data-arlen-live-component="orders-table"
  data-arlen-live-event="paginate">
  Next
</a>
```

The runtime sends the live request headers:

- `X-Arlen-Live: true`
- `X-Arlen-Live-Target`
- `X-Arlen-Live-Swap`
- `X-Arlen-Live-Component`
- `X-Arlen-Live-Event`
- `X-Arlen-Live-Source`

## 4. Controller APIs

`ALNController` exposes the main live helpers:

- `isLiveRequest`
- `liveMetadata`
- `renderLiveOperations:error:`
- `renderLiveTemplate:target:action:context:error:`
- `renderLiveNavigateTo:replace:`
- `publishLiveOperations:onChannel:error:`

`renderLiveTemplate:target:action:context:error:` can use the current live
request metadata when `target` or `action` is omitted. That keeps the target
selector and swap mode in the template markup instead of duplicating it in the
controller.

Example controller pattern:

```objc
- (id)filter:(ALNContext *)ctx {
  NSError *error = nil;
  NSDictionary *viewContext = @{
    @"orders" : [self filteredOrders],
  };

  if ([self isLiveRequest]) {
    if (![self renderLiveTemplate:@"orders/_table"
                           target:nil
                           action:nil
                          context:viewContext
                            error:&error]) {
      [self setStatus:500];
      [self renderText:error.localizedDescription ?: @"live render failed\n"];
    }
    return nil;
  }

  [self renderTemplate:@"orders/index" context:viewContext error:&error];
  return nil;
}
```

## 5. Full-Page Navigation vs Live Navigation

For ordinary HTML requests, use normal `renderTemplate:` and `redirectTo:`.

For live requests, use:

```objc
[self renderLiveNavigateTo:@"/orders/42" replace:NO];
```

If live serialization fails, Arlen falls back to a normal `302` redirect.

## 6. Push Updates

Phase 25 integrates with the existing realtime hub. The browser runtime watches
elements with `data-arlen-live-stream` and opens websocket subscriptions.

Example markup:

```html
<section id="notifications" data-arlen-live-stream="/ws/channel/live.notifications"></section>
```

Example publish path:

```objc
NSError *error = nil;
[self publishLiveOperations:@[
  [ALNLive appendOperationForTarget:@"#notifications"
                               html:@"<li>Build complete</li>"]
]
                         onChannel:@"live.notifications"
                             error:&error];
```

The pushed message is the same live JSON payload used for ordinary request
responses.

## 7. Verification

Focused verification lane:

```bash
source tools/source_gnustep_env.sh
make phase25-live-tests
```

Current unit coverage includes:

- protocol normalization and serialization
- controller live rendering and publish helpers
- built-in `/arlen/live.js` runtime route behavior
