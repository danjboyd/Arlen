# ALNRoutePolicyMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNRoutePolicyMiddleware.h`

Built-in middleware implementation ready to register on an application.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `validateSecurityConfiguration:` | `+ (nullable NSError *)validateSecurityConfiguration:(NSDictionary *)config;` | Perform `validate security configuration` for `ALNRoutePolicyMiddleware`. | Call on the class type, not on an instance. |
