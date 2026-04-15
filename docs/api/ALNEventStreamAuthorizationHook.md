# ALNEventStreamAuthorizationHook

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNEventStream.h`

Lifecycle hook protocol for `ALNEventStreamAuthorizationHook` implementations.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `authorizeEventStreamAppendToStream:event:requestContext:error:` | `- (BOOL)authorizeEventStreamAppendToStream:(NSString *)streamID event:(NSDictionary *)event requestContext:(ALNEventStreamRequestContext *)requestContext error:(NSError *_Nullable *_Nullable)error;` | Perform `authorize event stream append to stream` for `ALNEventStreamAuthorizationHook`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `authorizeEventStreamReplayOfStream:afterSequence:requestContext:error:` | `- (BOOL)authorizeEventStreamReplayOfStream:(NSString *)streamID afterSequence:(nullable NSNumber *)sequence requestContext:(ALNEventStreamRequestContext *)requestContext error:(NSError *_Nullable *_Nullable)error;` | Perform `authorize event stream replay of stream` for `ALNEventStreamAuthorizationHook`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `authorizeEventStreamSubscribeToStream:requestContext:error:` | `- (BOOL)authorizeEventStreamSubscribeToStream:(NSString *)streamID requestContext:(ALNEventStreamRequestContext *)requestContext error:(NSError *_Nullable *_Nullable)error;` | Perform `authorize event stream subscribe to stream` for `ALNEventStreamAuthorizationHook`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
