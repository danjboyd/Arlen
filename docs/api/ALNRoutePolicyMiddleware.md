# ALNRoutePolicyMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNRoutePolicyMiddleware.h`

Built-in middleware implementation ready to register on an application.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `validateSecurityConfiguration:` | `+ (nullable NSError *)validateSecurityConfiguration:(NSDictionary *)config;` | Perform `validate security configuration` for `ALNRoutePolicyMiddleware`. | Call on the class type, not on an instance. |
| `context:canListRoute:` | `+ (BOOL)context:(ALNContext *)context canListRoute:(ALNRoute *)route;` | Check catalog visibility against current caller identity, source IP, and route policy metadata without executing the route. | Use for metadata listings. Invocation must still enforce the full policy with concrete route arguments; this check does not run handlers or guards. |
