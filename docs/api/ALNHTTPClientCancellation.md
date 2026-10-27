# ALNHTTPClientCancellation

- Kind: `interface`
- Header: `src/Arlen/Support/ALNHTTPClient.h`

Thread-safe, single-use cancellation token for an outbound HTTP stream. Cancellation is permanent, works during transport silence, and may be requested from any thread. See [Streaming HTTP](../HTTP_CLIENT.md#incremental-response-delivery).

## Typical Usage

```objc
ALNHTTPClientCancellation *stop = [ALNHTTPClientCancellation new];
// Store before starting streamRequest:cancellation:onResponse:onData:error:.
// A Stop button or browser disconnect may call this from another thread:
[stop cancel];
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `cancelled` | `BOOL` | `nonatomic, readonly, getter=isCancelled` | Thread-safe cancellation state. Once YES it remains YES; create a new token for another operation. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `cancel` | `- (void)cancel;` | Permanently request cancellation of this operation from any thread. | Calling repeatedly is safe. A pre-cancelled token prevents the stream from connecting. Cancellation does not interrupt callback code; callbacks must return promptly. |
