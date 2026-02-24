# ALNRouteMatch

- Kind: `interface`
- Header: `src/Arlen/MVC/Routing/ALNRoute.h`

Route match result object containing matched route metadata and extracted route params.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `route` | `ALNRoute *` | `nonatomic, strong, readonly` | Public `route` property available on `ALNRouteMatch`. |
| `params` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `params` property available on `ALNRouteMatch`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithRoute:params:` | `- (instancetype)initWithRoute:(ALNRoute *)route params:(NSDictionary *)params;` | Initialize and return a new `ALNRouteMatch` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
