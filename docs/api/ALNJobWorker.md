# ALNJobWorker

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Worker orchestration helper that leases due jobs and executes them through a runtime callback.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `maxJobsPerRun` | `NSUInteger` | `nonatomic, assign` | Public `maxJobsPerRun` property available on `ALNJobWorker`. |
| `retryDelaySeconds` | `NSTimeInterval` | `nonatomic, assign` | Public `retryDelaySeconds` property available on `ALNJobWorker`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithJobsAdapter:` | `- (instancetype)initWithJobsAdapter:(id<ALNJobAdapter>)jobsAdapter;` | Initialize and return a new `ALNJobWorker` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `runDueJobsAt:runtime:error:` | `- (nullable ALNJobWorkerRunSummary *)runDueJobsAt:(nullable NSDate *)timestamp runtime:(id<ALNJobWorkerRuntime>)runtime error:(NSError *_Nullable *_Nullable)error;` | Lease and execute due jobs through a worker runtime callback. | Use small run limits per worker tick to keep throughput predictable. |
