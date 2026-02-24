# ALNFileMailAdapter

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Filesystem-backed mail adapter that writes deliveries to disk for auditing/testing.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithStorageDirectory:adapterName:error:` | `- (nullable instancetype)initWithStorageDirectory:(NSString *)storageDirectory adapterName:(nullable NSString *)adapterName error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNFileMailAdapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
