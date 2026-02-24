# ALNInMemoryJobAdapter

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

In-memory adapter implementation useful for development and tests.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithAdapterName:` | `- (instancetype)initWithAdapterName:(nullable NSString *)adapterName;` | Initialize and return a new `ALNInMemoryJobAdapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
