# ALNFileSystemAttachmentAdapter

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Filesystem-backed attachment adapter for durable binary storage.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithRootDirectory:adapterName:error:` | `- (nullable instancetype)initWithRootDirectory:(NSString *)rootDirectory adapterName:(nullable NSString *)adapterName error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNFileSystemAttachmentAdapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
