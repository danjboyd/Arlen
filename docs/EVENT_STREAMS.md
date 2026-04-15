# Durable Event Streams

Arlen Phase 33 adds a narrow durable event-stream seam between the existing
realtime transport helpers and higher-level module semantics.

Use this seam when your app needs:

- durable append with an authoritative committed sequence
- replay after reconnect
- explicit `resync_required` behavior when a cursor is too old
- the same stream consumed over websocket, SSE, or HTTP replay/polling

Do not use it for product semantics that belong above core, such as:

- conversation naming or assignment
- read/unread state
- typing indicators or presence
- operator workflow rules

Those remain app- or module-owned concerns layered on top of the seam.

## Core Contract

The core event shape is `ALNEventEnvelope`.

Required fields:

- `stream_id`
- `sequence`
- `event_id`
- `event_type`
- `occurred_at`
- `payload`

Important ownership rules:

- callers provide `stream_id`, `event_type`, `payload`, and optional
  `idempotency_key`, `actor`, or `metadata`
- the durable store assigns the authoritative `sequence`
- the framework/store normalizes `event_id` and `occurred_at`
- replay order is always committed sequence order

Correctness baseline:

- durable append is the source of truth
- live publish happens only after append commits
- replay always comes from the configured store, not broker retention
- clients must be ready to replay from a durable cursor after missed live
  delivery

## App Setup

`ALNApplication` owns the configured store, broker, and authorization hook.

Minimal setup:

```objc
#import <Arlen/Arlen.h>

@interface StreamsAuthHook : NSObject <ALNEventStreamAuthorizationHook>
@end

@implementation StreamsAuthHook

- (BOOL)authorizeEventStreamAppendToStream:(NSString *)streamID
                                     event:(NSDictionary *)event
                            requestContext:(ALNEventStreamRequestContext *)requestContext
                                     error:(NSError **)error {
  (void)streamID;
  (void)event;
  return requestContext.authSubject != nil;
}

- (BOOL)authorizeEventStreamReplayOfStream:(NSString *)streamID
                             afterSequence:(NSNumber *)sequence
                            requestContext:(ALNEventStreamRequestContext *)requestContext
                                     error:(NSError **)error {
  (void)streamID;
  (void)sequence;
  return requestContext.authSubject != nil;
}

- (BOOL)authorizeEventStreamSubscribeToStream:(NSString *)streamID
                               requestContext:(ALNEventStreamRequestContext *)requestContext
                                        error:(NSError **)error {
  (void)streamID;
  return requestContext.authSubject != nil;
}

@end

static void ConfigureRealtime(ALNApplication *app) {
  [app setEventStreamStore:[[ALNInMemoryEventStreamStore alloc] initWithAdapterName:@"memory"]];
  [app setEventStreamBroker:[[ALNInMemoryEventStreamBroker alloc] initWithAdapterName:@"memory"]];
  [app setEventStreamAuthorizationHook:[[StreamsAuthHook alloc] init]];
}
```

The in-memory store and broker are useful for local development and focused
tests. Production durability should come from a real store adapter.

## Controller Helpers

`ALNController` exposes the seam through one append path and three consumer
paths:

- `appendEventStreamEvent:toStream:error:`
- `renderEventStreamReplay:afterSequence:limit:replayWindow:error:`
- `renderSSEStream:afterSequence:limit:replayWindow:error:`
- `acceptWebSocketStream:afterSequence:limit:replayWindow:error:`

Append example:

```objc
- (id)createMessage:(ALNContext *)ctx {
  (void)ctx;
  NSString *body = [self stringParamForName:@"body"] ?: @"";
  NSError *error = nil;
  ALNEventStreamAppendResult *result =
      [self appendEventStreamEvent:@{
        @"event_type" : @"message_created",
        @"payload" : @{ @"body" : body },
        @"idempotency_key" : [self headerValueForName:@"Idempotency-Key"] ?: @""
      }
                        toStream:@"ownerconnect:conversation:123"
                           error:&error];
  if (result == nil) {
    [self setStatus:(error.code == ALNEventStreamErrorUnauthorized) ? 403 : 500];
    return [self renderJSON:@{ @"error" : error.localizedDescription ?: @"append failed" }
                      error:NULL];
  }
  return [self renderJSON:[result.committedEvent dictionaryRepresentation] error:NULL];
}
```

Replay/poll example:

```objc
- (id)events:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  if (![self renderEventStreamReplay:@"ownerconnect:conversation:123"
                       afterSequence:[self queryIntegerForName:@"after_sequence"]
                               limit:100
                        replayWindow:500
                               error:&error]) {
    [self setStatus:(error.code == ALNEventStreamErrorUnauthorized) ? 403 : 500];
    [self renderText:error.localizedDescription ?: @"replay failed\n"];
  }
  return nil;
}
```

SSE and websocket use the same stream/cursor contract:

```objc
- (id)sse:(ALNContext *)ctx {
  (void)ctx;
  [self renderSSEStream:@"ownerconnect:conversation:123"
          afterSequence:[self queryIntegerForName:@"after_sequence"]
                  limit:100
           replayWindow:500
                  error:NULL];
  return nil;
}

- (id)ws:(ALNContext *)ctx {
  (void)ctx;
  [self acceptWebSocketStream:@"ownerconnect:conversation:123"
                afterSequence:[self queryIntegerForName:@"after_sequence"]
                        limit:100
                 replayWindow:500
                        error:NULL];
  return nil;
}
```

## Replay and `resync_required`

Cursor semantics are sequence-based in the first shipping slice.

- replay is always `afterSequence`
- the server may cap replay by `limit`
- `replayWindow` defines how far back the server will satisfy incremental
  replay before requiring a full resync
- when the requested cursor cannot be satisfied, Arlen returns a deterministic
  `resync_required` result instead of silently falling back

The important operational point is that a failed or missed live delivery does
not imply data loss if the client still has a valid durable cursor.

## TypeScript Consumer Surface

Phase 33 extends the existing generated TypeScript package with
`src/realtime.ts`.

The plain consumer surface includes:

- `ArlenRealtimeEventEnvelope`
- `ArlenRealtimeCursor`
- `ArlenRealtimeReplayResult`
- `ArlenRealtimeResyncRequired`
- `ArlenRealtimeStreamClient`
- `arlenRealtimeTransportPlan`
- `arlenRealtimeReplayPath`

Example:

```ts
import { ArlenRealtimeStreamClient } from './generated/arlen/src/realtime';

const stream = new ArlenRealtimeStreamClient({
  baseUrl: 'https://example.test',
  streamId: 'ownerconnect:conversation:123',
  cursor: 41,
  transports: ['websocket', 'sse', 'poll'],
});

await stream.connect();
```

This first client layer is transport-neutral and does not require React.

## Choosing Raw Realtime vs. Durable Streams

Use raw realtime transport helpers when:

- the update is transient
- reconnect replay is not required
- process-local fanout is acceptable

Use the durable event-stream seam when:

- committed history matters
- reconnect/replay correctness matters
- subscription auth needs to be explicit and repeatable
- websocket, SSE, and polling should share one delivery contract

## Module Boundary

Phase 33 closes with a narrow core boundary.

Reasonable follow-on work above this seam includes:

- first-party store or broker adapters
- conversation modules
- presence or participant semantics
- read-cursor or unread helpers
- optional React-facing helpers above the plain generated client

Those should build on this seam rather than expand the core contract directly.
