# Live UI Guide

Arlen's Phase 25 live UI layer is fragment-first. It does not try to be a
whole-page stateful diff engine. The current model is:

- controllers return HTML fragments or explicit live operations
- the built-in browser runtime applies targeted DOM updates
- the same payload shape can be returned over HTTP or pushed over websockets
- links, forms, and regions remain ordinary HTML authoring surfaces

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
- `Cache-Control: no-store`
- `Vary: Accept, X-Arlen-Live`

Payload shape:

```json
{
  "version": "arlen-live-v1",
  "operations": [
    { "op": "update", "target": "#orders", "html": "<li>Alpha</li>" }
  ],
  "meta": {
    "request_id": "req-123",
    "route": "orders.index",
    "method": "GET"
  }
}
```

Supported operations:

- `replace`
- `update`
- `append`
- `prepend`
- `remove`
- `upsert`
- `discard`
- `navigate`
- `dispatch`

`upsert` and `discard` are keyed collection operations. They carry:

- `container`: CSS selector for the keyed list/table/feed root
- `key`: stable keyed item identifier
- `target`: derived keyed selector for diagnostics/debugging

## 3. Authoring Live Links and Forms

Mark links or forms with `data-arlen-live` so the runtime intercepts them.

Common authoring attributes:

- `data-arlen-live-target`: CSS selector to patch
- `data-arlen-live-swap`: `replace`, `update`, `append`, or `prepend`
- `data-arlen-live-component`: stable component identifier for the request
- `data-arlen-live-event`: event name describing the user action
- `data-arlen-live-container`: keyed collection root selector
- `data-arlen-live-key`: keyed collection item identifier

Example form:

```html
<form
  method="get"
  action="/orders/filter"
  data-arlen-live
  data-arlen-live-target="#orders-table"
  data-arlen-live-swap="update"
  data-arlen-live-component="orders-table"
  data-arlen-live-event="filter">
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

The runtime sends these headers when present:

- `X-Arlen-Live: true`
- `X-Arlen-Live-Target`
- `X-Arlen-Live-Swap`
- `X-Arlen-Live-Component`
- `X-Arlen-Live-Event`
- `X-Arlen-Live-Source`
- `X-Arlen-Live-Container`
- `X-Arlen-Live-Key`
- `X-Arlen-Live-Poll`
- `X-Arlen-Live-Defer`
- `X-Arlen-Live-Lazy`

## 4. Live Regions: Polling, Lazy, and Deferred

Any element with `data-arlen-live-src` becomes a live region.

Optional region attributes:

- `data-arlen-live-src`: URL to fetch
- `data-arlen-live-target`: region target selector
- `data-arlen-live-swap`: how HTML/live responses should patch the target
- `data-arlen-live-poll`: interval (`2000`, `500ms`, `4s`, `1m`)
- `data-arlen-live-lazy`: hydrate on viewport entry
- `data-arlen-live-defer`: wait before hydrating

Example polling region:

```html
<section
  id="live-pulse"
  data-arlen-live-src="/orders/pulse"
  data-arlen-live-target="#live-pulse"
  data-arlen-live-swap="update"
  data-arlen-live-poll="4s">
  <p>Loading...</p>
</section>
```

If the region endpoint returns HTML instead of live JSON, the runtime applies
that HTML directly to the target region using the configured swap mode.

## 5. Keyed Collections

Keyed collection updates are for feeds, lists, and tables where item identity
matters more than a whole-region rerender.

Markup contract:

- collection root gets an explicit selector such as `#feed`
- each item carries `data-arlen-live-key`
- optional empty placeholder carries `data-arlen-live-empty`

Example:

```html
<ul id="feed">
  <li data-arlen-live-key="alpha">Alpha</li>
  <li data-arlen-live-empty hidden>No items yet.</li>
</ul>
```

Server helpers:

- `upsertKeyedOperationForContainer:key:html:prepend:`
- `removeKeyedOperationForContainer:key:`
- `renderLiveKeyedTemplate:container:key:prepend:context:error:`
- `publishLiveKeyedTemplate:container:key:prepend:context:onChannel:error:`

## 6. Controller APIs

`ALNController` exposes the main live helpers:

- `isLiveRequest`
- `liveMetadata`
- `renderLiveOperations:error:`
- `renderLiveTemplate:target:action:context:error:`
- `renderLiveKeyedTemplate:container:key:prepend:context:error:`
- `renderLiveNavigateTo:replace:`
- `publishLiveOperations:onChannel:error:`
- `publishLiveKeyedTemplate:container:key:prepend:context:onChannel:error:`

`renderLiveTemplate:target:action:context:error:` and the keyed helper can use
request metadata when the explicit target/container/key/action arguments are
omitted.

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

## 7. Push Updates

The runtime watches `data-arlen-live-stream` elements and opens websocket
subscriptions.

Example markup:

```html
<section data-arlen-live-stream="/ws/channel/live.notifications"></section>
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

The pushed message is the same live JSON payload used for ordinary HTTP live
responses.

## 8. Upload Progress and Failure Signals

For live forms with file inputs, or forms that set
`data-arlen-live-upload-progress` / `data-arlen-live-progress-target`, the
runtime uses `XMLHttpRequest` so upload progress can be surfaced through:

- progress target attributes:
  - `data-arlen-live-upload-loaded`
  - `data-arlen-live-upload-total`
  - `data-arlen-live-upload-percent`
- DOM events:
  - `arlen:live:upload-progress`
  - `arlen:live:backpressure`
  - `arlen:live:auth-expired`
  - `arlen:live:stream-open`
  - `arlen:live:stream-closed`

## 9. Example and Verification

The checked-in tech demo now includes a live page at:

- `/tech-demo/live`

Focused verification:

```bash
source tools/source_gnustep_env.sh
make phase25-live-tests
make phase25-confidence
```

`phase25-confidence` builds the live suite, boots the tech demo server, and
records a smoke artifact set under `build/release_confidence/phase25/`.
