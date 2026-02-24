# ALNRedisCacheAdapter

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Redis-backed cache adapter implementation compatible with `ALNCacheAdapter` semantics.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithURLString:namespace:adapterName:error:` | `- (nullable instancetype)initWithURLString:(NSString *)urlString namespace:(nullable NSString *)namespacePrefix adapterName:(nullable NSString *)adapterName error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNRedisCacheAdapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
