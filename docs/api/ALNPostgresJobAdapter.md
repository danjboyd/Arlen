# ALNPostgresJobAdapter

- Kind: `interface`
- Header: `src/Arlen/Support/ALNPostgresJobAdapter.h`

PostgreSQL durable queue with transactional enqueue, fenced renewable leases, retained results, replay, and shared queue controls. See docs/DURABLE_JOBS.md.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `database` | `ALNPg *` | `nonatomic, strong, readonly` | Public `database` property available on `ALNPostgresJobAdapter`. |
| `namespaceName` | `NSString *` | `nonatomic, copy, readonly` | Public `namespaceName` property available on `ALNPostgresJobAdapter`. |
| `leaseDurationSeconds` | `NSTimeInterval` | `nonatomic, assign, readonly` | Public `leaseDurationSeconds` property available on `ALNPostgresJobAdapter`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithDatabase:namespace:leaseDurationSeconds:error:` | `- (nullable instancetype)initWithDatabase:(ALNPg *)database namespace:(NSString *)namespaceName leaseDurationSeconds:(NSTimeInterval)leaseDurationSeconds error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNPostgresJobAdapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `schemaStatements` | `+ (NSArray<NSString *> *)schemaStatements;` | Perform `schema statements` for `ALNPostgresJobAdapter`. | Call on the class type, not on an instance. |
| `installSchemaWithError:` | `- (BOOL)installSchemaWithError:(NSError *_Nullable *_Nullable)error;` | Perform `install schema with error` for `ALNPostgresJobAdapter`. | Check the return value to confirm the operation succeeded. |
| `enqueueJobNamed:payload:options:onConnection:error:` | `- (nullable NSString *)enqueueJobNamed:(NSString *)name payload:(nullable NSDictionary *)payload options:(nullable NSDictionary *)options onConnection:(id<ALNDatabaseConnection>)connection error:(NSError *_Nullable *_Nullable)error;` | Enqueue a background job for async processing. | Pass `NSError **` and treat a `nil` result as failure. |
| `jobsWithState:error:` | `- (nullable NSArray<ALNJobEnvelope *> *)jobsWithState:(NSString *)state error:(NSError *_Nullable *_Nullable)error;` | Perform `jobs with state` for `ALNPostgresJobAdapter`. | Pass `NSError **` and treat a `nil` result as failure. |
| `leasedJobsSnapshot` | `- (NSArray *)leasedJobsSnapshot;` | Perform `leased jobs snapshot` for `ALNPostgresJobAdapter`. | Read this value when you need current runtime/request state. |
| `resetWithError:` | `- (BOOL)resetWithError:(NSError *_Nullable *_Nullable)error;` | Reset state to a clean baseline for testing or maintenance. | Check the return value to confirm the operation succeeded. |
