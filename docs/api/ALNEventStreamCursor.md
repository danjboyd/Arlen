# ALNEventStreamCursor

- Kind: `interface`
- Header: `src/Arlen/Support/ALNEventStream.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `streamID` | `NSString *` | `nonatomic, copy, readonly` | Public `streamID` property available on `ALNEventStreamCursor`. |
| `sequence` | `NSUInteger` | `nonatomic, assign, readonly` | Public `sequence` property available on `ALNEventStreamCursor`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithStreamID:sequence:` | `- (instancetype)initWithStreamID:(NSString *)streamID sequence:(NSUInteger)sequence;` | Initialize and return a new `ALNEventStreamCursor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
