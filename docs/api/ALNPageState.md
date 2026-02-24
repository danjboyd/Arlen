# ALNPageState

- Kind: `interface`
- Header: `src/Arlen/MVC/Controller/ALNPageState.h`

Page-state helper for namespaced key/value persistence across requests in compatibility workflows.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `pageKey` | `NSString *` | `nonatomic, copy, readonly` | Public `pageKey` property available on `ALNPageState`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithContext:pageKey:` | `- (instancetype)initWithContext:(ALNContext *)context pageKey:(NSString *)pageKey;` | Initialize and return a new `ALNPageState` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `allValues` | `- (NSDictionary *)allValues;` | Return all values currently stored in this state container. | Read this value when you need current runtime/request state. |
| `valueForKey:` | `- (nullable id)valueForKey:(NSString *)key;` | Return one value by key from the current state container. | Capture the returned value and propagate errors/validation as needed. |
| `setValue:forKey:` | `- (void)setValue:(nullable id)value forKey:(NSString *)key;` | Set one value by key in the current state container. | Call before downstream behavior that depends on this updated value. |
| `clear` | `- (void)clear;` | Clear all values in this state container. | Call for side effects; this method does not return a value. |
