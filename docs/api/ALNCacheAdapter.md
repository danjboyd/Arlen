# ALNCacheAdapter

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNServices.h`

Cache adapter protocol for set/get/remove/clear operations with optional TTL semantics.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `setObject:forKey:ttlSeconds:error:` | `- (BOOL)setObject:(nullable id)object forKey:(NSString *)key ttlSeconds:(NSTimeInterval)ttlSeconds error:(NSError *_Nullable *_Nullable)error;` | Set cache value with optional TTL for one key. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `objectForKey:atTime:error:` | `- (nullable id)objectForKey:(NSString *)key atTime:(NSDate *)timestamp error:(NSError *_Nullable *_Nullable)error;` | Read cache value for one key using a point-in-time clock. | Pass `NSError **` and treat a `nil` result as failure. |
| `removeObjectForKey:error:` | `- (BOOL)removeObjectForKey:(NSString *)key error:(NSError *_Nullable *_Nullable)error;` | Remove one cache entry by key. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `clearWithError:` | `- (BOOL)clearWithError:(NSError *_Nullable *_Nullable)error;` | Clear all entries for this adapter/store. | Check the return value to confirm the operation succeeded. |
