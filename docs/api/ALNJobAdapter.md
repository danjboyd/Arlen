# ALNJobAdapter

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNServices.h`

Job adapter protocol for enqueue/dequeue/ack/retry operations and queue state diagnostics.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `enqueueJobNamed:payload:options:error:` | `- (nullable NSString *)enqueueJobNamed:(NSString *)name payload:(nullable NSDictionary *)payload options:(nullable NSDictionary *)options error:(NSError *_Nullable *_Nullable)error;` | Enqueue a background job with optional scheduling/retry metadata. | Pass idempotency/retry metadata in `options` when you need deterministic re-enqueue behavior. |
| `dequeueDueJobAt:error:` | `- (nullable ALNJobEnvelope *)dequeueDueJobAt:(NSDate *)timestamp error:(NSError *_Nullable *_Nullable)error;` | Lease the next due background job at a timestamp. | Workers should poll with clock source used for scheduling and retry calculations. |
| `acknowledgeJobID:error:` | `- (BOOL)acknowledgeJobID:(NSString *)jobID error:(NSError *_Nullable *_Nullable)error;` | Acknowledge completion for a previously leased job. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `retryJob:delaySeconds:error:` | `- (BOOL)retryJob:(ALNJobEnvelope *)job delaySeconds:(NSTimeInterval)delaySeconds error:(NSError *_Nullable *_Nullable)error;` | Requeue a leased job with retry delay. | Use bounded retry delays; combine with dead-letter handling after max attempts. |
| `pendingJobsSnapshot` | `- (NSArray *)pendingJobsSnapshot;` | Return snapshot of currently pending jobs. | Read this value when you need current runtime/request state. |
| `deadLetterJobsSnapshot` | `- (NSArray *)deadLetterJobsSnapshot;` | Return snapshot of dead-lettered jobs. | Read this value when you need current runtime/request state. |
| `reset` | `- (void)reset;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |
