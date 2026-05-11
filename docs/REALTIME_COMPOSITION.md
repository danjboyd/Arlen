# Realtime and Composition

Arlen adds baseline realtime and app-composition contracts to Arlen.

## 1. Controller Realtime APIs

`ALNController` now provides:

- `acceptWebSocketEcho`
- `acceptWebSocketChannel:(NSString *)channel`
- `renderSSEEvents:(NSArray *)events`

These APIs are explicit and opt-in. Standard HTTP routes continue to work unchanged.

## 2. WebSocket Contract

Runtime support is implemented in `ALNHTTPServer` with RFC6455 text-frame baseline behavior.

Handshake requirements:

- `GET` request
- `Upgrade: websocket`
- `Connection: Upgrade`
- `Sec-WebSocket-Key`

Controller workflow:

1. Route action calls `acceptWebSocketEcho` or `acceptWebSocketChannel:`.
2. Server emits `101 Switching Protocols` and transitions to websocket frame loop.

Modes:

- `echo`: server returns each received text frame to same client.
- `channel`: inbound text messages are published to channel subscribers via `ALNRealtimeHub`.

Notes:

- Text frames are the baseline contract.
- Ping/Pong and close control frames are handled.

## 3. SSE Contract

`renderSSEEvents:` formats `text/event-stream` responses from dictionaries containing:

- `id` (optional)
- `event` (optional)
- `retry` (optional)
- `data` (string or JSON-serializable object)

Example event dictionary:

```objc
@{
  @"id" : @"1",
  @"event" : @"tick",
  @"data" : @{ @"index" : @1 },
  @"retry" : @(1000),
}
```

## 4. Realtime Pub/Sub Abstraction

`ALNRealtimeHub` provides deterministic in-memory channel fanout:

- `subscribeChannel:subscriber:`
- `publishMessage:onChannel:`
- `unsubscribe:`

The hub is thread-safe and used by websocket channel mode.

## 4.1 Durable Event-Stream Seam

Arlen now also ships a durable core/service event-stream seam under
`ALNEventStream`:

- `ALNEventEnvelope`
- `ALNEventStreamCursor`
- `ALNEventStreamRequestContext`
- `ALNEventStreamStore`
- `ALNEventStreamAuthorizationHook`
- `ALNInMemoryEventStreamStore`
- `ALNEventStreamBroker`
- `ALNInMemoryEventStreamBroker`
- `ALNEventStreamService`

Current shipped scope for that seam:

- canonical event envelope shape for named append-only streams
- authoritative sequence assignment in the configured store adapter
- replay after sequence through the same store seam
- request-derived authorization context for append/replay/subscribe decisions
- deny-by-default authorization entrypoints on `ALNApplication`
- idempotent append retries scoped by `(stream_id, idempotency_key)`
- replay-window enforcement with deterministic `resync_required` results
- publish-after-commit live fanout through the broker seam
- websocket stream subscribe helpers layered on the same replay/auth contract
- SSE stream subscribe helpers layered on the same replay/auth contract
- HTTP replay/poll helpers layered on the same replay/auth contract
- a plain generated TypeScript consumer surface in the generated TypeScript package under
  `src/realtime.ts`

Current non-goals still remain:

- conversation/presence/read-cursor semantics
- broker-backed multi-node fanout without an explicit adapter
- React-specific helpers as part of the first shipping slice

See [Durable Event Streams](EVENT_STREAMS.md) for app-author usage and the
module boundary.

## 5. Live UI Baseline

Arlen adds a fragment-first live UI layer on top of the realtime
transport baseline.

Current pieces:

- `ALNLive` live-response protocol (`application/vnd.arlen.live+json`)
- built-in browser runtime at `/arlen/live.js`
- delegated interception for `a[data-arlen-live]` and `form[data-arlen-live]`
- optional request metadata via:
  - `data-arlen-live-target`
  - `data-arlen-live-swap`
  - `data-arlen-live-component`
  - `data-arlen-live-event`
- controller helpers:
  - `isLiveRequest`
  - `liveMetadata`
  - `renderLiveOperations:error:`
  - `renderLiveTemplate:target:action:context:error:`
  - `renderLiveNavigateTo:replace:`
  - `publishLiveOperations:onChannel:error:`

See [Live UI Guide](LIVE_UI.md) for authoring examples and the current scope
boundary.

## 6. App Mounting / Embedding

`ALNApplication` now supports:

- `mountApplication:atPrefix:`

Behavior:

- parent app rewrites request path under mount prefix and dispatches to mounted app
- mounted response is returned directly
- parent adds `X-Arlen-Mount-Prefix` header

This enables modular app composition while preserving existing route/controller contracts.

## 7. Built-In Boomhauer Realtime Routes

Current sample routes in `boomhauer`:

- `/ws/echo`
- `/ws/channel/:channel`
- `/sse/ticker`
- mounted app at `/embedded`:
  - `/embedded/status`
  - `/embedded/api/status`

## 8. Verification Coverage

Coverage includes:

- unit tests for `ALNRealtimeHub`, mount rewriting, controller realtime helpers
- integration tests for websocket echo, channel fanout, concurrent SSE requests, and mounted route composition
