# ALNJobWorkerRunSummary

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Summary payload for one worker run, including lease/ack/retry/error counters.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `leasedCount` | `NSUInteger` | `nonatomic, assign, readonly` | Public `leasedCount` property available on `ALNJobWorkerRunSummary`. |
| `acknowledgedCount` | `NSUInteger` | `nonatomic, assign, readonly` | Public `acknowledgedCount` property available on `ALNJobWorkerRunSummary`. |
| `retriedCount` | `NSUInteger` | `nonatomic, assign, readonly` | Public `retriedCount` property available on `ALNJobWorkerRunSummary`. |
| `handlerErrorCount` | `NSUInteger` | `nonatomic, assign, readonly` | Public `handlerErrorCount` property available on `ALNJobWorkerRunSummary`. |
| `reachedRunLimit` | `BOOL` | `nonatomic, assign, readonly` | Public `reachedRunLimit` property available on `ALNJobWorkerRunSummary`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithLeasedCount:acknowledgedCount:retriedCount:handlerErrorCount:reachedRunLimit:` | `- (instancetype)initWithLeasedCount:(NSUInteger)leasedCount acknowledgedCount:(NSUInteger)acknowledgedCount retriedCount:(NSUInteger)retriedCount handlerErrorCount:(NSUInteger)handlerErrorCount reachedRunLimit:(BOOL)reachedRunLimit;` | Initialize and return a new `ALNJobWorkerRunSummary` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
