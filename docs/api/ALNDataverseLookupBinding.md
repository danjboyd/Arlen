# ALNDataverseLookupBinding

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `bindPath` | `NSString *` | `nonatomic, copy, readonly` | Public `bindPath` property available on `ALNDataverseLookupBinding`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `bindingWithBindPath:` | `+ (instancetype)bindingWithBindPath:(NSString *)bindPath;` | Perform `binding with bind path` for `ALNDataverseLookupBinding`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `bindingWithEntitySetName:recordID:error:` | `+ (nullable instancetype)bindingWithEntitySetName:(NSString *)entitySetName recordID:(NSString *)recordID error:(NSError *_Nullable *_Nullable)error;` | Perform `binding with entity set name` for `ALNDataverseLookupBinding`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseLookupBinding` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithBindPath:` | `- (instancetype)initWithBindPath:(NSString *)bindPath NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseLookupBinding` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
