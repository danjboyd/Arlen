# Realtime and Composition

Phase 3D adds baseline realtime and app-composition contracts to Arlen.

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

## 5. App Mounting / Embedding

`ALNApplication` now supports:

- `mountApplication:atPrefix:`

Behavior:

- parent app rewrites request path under mount prefix and dispatches to mounted app
- mounted response is returned directly
- parent adds `X-Arlen-Mount-Prefix` header

This enables modular app composition while preserving existing route/controller contracts.

## 6. Built-In Boomhauer Phase 3D Routes

Current sample routes in `boomhauer`:

- `/ws/echo`
- `/ws/channel/:channel`
- `/sse/ticker`
- mounted app at `/embedded`:
  - `/embedded/status`
  - `/embedded/api/status`

## 7. Verification Coverage

Phase 3D coverage includes:

- unit tests for `ALNRealtimeHub`, mount rewriting, controller realtime helpers
- integration tests for websocket echo, channel fanout, concurrent SSE requests, and mounted route composition
