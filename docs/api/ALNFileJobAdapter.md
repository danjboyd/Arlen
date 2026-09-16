# ALNFileJobAdapter

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Filesystem-persisted job queue for one adapter instance; no cross-process coordination or crashed-worker lease recovery.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithStoragePath:adapterName:error:` | `- (nullable instancetype)initWithStoragePath:(NSString *)storagePath adapterName:(nullable NSString *)adapterName error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNFileJobAdapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
