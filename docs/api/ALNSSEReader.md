# ALNSSEReader

- Kind: `interface`
- Header: `src/Arlen/Support/ALNSSEReader.h`

Bounded incremental SSE framing for HTTP-client chunks. Strict UTF-8; synchronous callbacks; no retry, reconnect or vendor terminal semantics. Apps must require their own terminal event.

## Typical Usage

```objc
ALNSSEReader *reader = [ALNSSEReader new];
BOOL parsed = [reader consumeData:chunk onEvent:^BOOL(ALNSSEEvent *event) {
  // Validate event.data using the application protocol.
  return YES;
} error:&error];
// At HTTP EOF: discard any unfinished event, without certifying app completion.
BOOL finished = [reader finishWithError:&error];
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `maxLineBytes` | `NSUInteger` | `nonatomic, assign, readonly` | Maximum raw bytes per line, excluding CR/LF and including the initial BOM. Default 65536. |
| `maxEventBytes` | `NSUInteger` | `nonatomic, assign, readonly` | Maximum accumulated UTF-8 data bytes plus one LF per data field. Default 1048576. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init;` | Construct a reader with 65536-byte lines and 1048576-byte event data. | Use one reader per HTTP response, on a single caller thread. |
| `initWithMaxLineBytes:maxEventBytes:error:` | `- (nullable instancetype)initWithMaxLineBytes:(NSUInteger)maxLineBytes maxEventBytes:(NSUInteger)maxEventBytes error:(NSError *_Nullable *_Nullable)error;` | Construct a reader with explicit positive byte limits; zero fails. | Event limits count one LF per data field, including the LF removed at dispatch. |
| `consumeData:onEvent:error:` | `- (BOOL)consumeData:(NSData *)data onEvent:(ALNSSEEventHandler)onEvent error:(NSError *_Nullable *_Nullable)error;` | Consume arbitrary byte chunks and dispatch complete events inline. | Returns NO permanently on strict UTF-8, limit, state or handler-stop errors. Do not reenter; handler exceptions propagate and stop parsing. See [HTTP client](../HTTP_CLIENT.md#bounded-sse-reader). |
| `finishWithError:` | `- (BOOL)finishWithError:(NSError *_Nullable *_Nullable)error;` | Close the reader and discard unfinished input without dispatching. | Repeated finish succeeds. Success is not application completion: require an app-defined terminal event. |
