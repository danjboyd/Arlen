# ALNDurableJobAdapter

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNServices.h`

Durable jobs contract for fenced completion, renewal, status/results, replay, and shared queue controls.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `jobsWithState:error:` | `- (nullable NSArray<ALNJobEnvelope *> *)jobsWithState:(NSString *)state error:(NSError *_Nullable *_Nullable)error;` | Perform `jobs with state` for `ALNDurableJobAdapter`. | Pass `NSError **` and treat a `nil` result as failure. |
| `renewJob:error:` | `- (BOOL)renewJob:(ALNJobLease *)job error:(NSError *_Nullable *_Nullable)error;` | Perform `renew job` for `ALNDurableJobAdapter`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `completeJob:result:error:` | `- (BOOL)completeJob:(ALNJobLease *)job result:(nullable id)result error:(NSError *_Nullable *_Nullable)error;` | Perform `complete job` for `ALNDurableJobAdapter`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `retryJob:delaySeconds:failureMessage:error:` | `- (BOOL)retryJob:(ALNJobEnvelope *)job delaySeconds:(NSTimeInterval)delaySeconds failureMessage:(nullable NSString *)failureMessage error:(NSError *_Nullable *_Nullable)error;` | Reschedule a failed job with backoff semantics. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `jobStatusForID:error:` | `- (nullable NSDictionary *)jobStatusForID:(NSString *)jobID error:(NSError *_Nullable *_Nullable)error;` | Perform `job status for id` for `ALNDurableJobAdapter`. | Pass `NSError **` and treat a `nil` result as failure. |
| `setQueue:state:error:` | `- (BOOL)setQueue:(NSString *)queue state:(NSString *)state error:(NSError *_Nullable *_Nullable)error;` | Set or override the current value for this concern. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `queueStatesWithError:` | `- (nullable NSArray<NSDictionary *> *)queueStatesWithError:(NSError *_Nullable *_Nullable)error;` | Perform `queue states with error` for `ALNDurableJobAdapter`. | Treat returned collection values as snapshots unless the API documents mutability. |
| `replayJobID:idempotencyKey:delaySeconds:error:` | `- (nullable NSString *)replayJobID:(NSString *)jobID idempotencyKey:(NSString *)idempotencyKey delaySeconds:(NSTimeInterval)delaySeconds error:(NSError *_Nullable *_Nullable)error;` | Perform `replay job id` for `ALNDurableJobAdapter`. | Pass `NSError **` and treat a `nil` result as failure. |
