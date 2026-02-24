# ALNRouter

- Kind: `interface`
- Header: `src/Arlen/MVC/Routing/ALNRouter.h`

Route registry and matcher with support for route grouping, guard actions, and format constraints.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `addRouteMethod:path:name:controllerClass:action:` | `- (ALNRoute *)addRouteMethod:(NSString *)method path:(NSString *)path name:(nullable NSString *)name controllerClass:(Class)controllerClass action:(NSString *)action;` | Add this item to the current runtime collection. | Call during bootstrap/setup before this behavior is exercised. |
| `addRouteMethod:path:name:formats:controllerClass:guardAction:action:` | `- (ALNRoute *)addRouteMethod:(NSString *)method path:(NSString *)path name:(nullable NSString *)name formats:(nullable NSArray *)formats controllerClass:(Class)controllerClass guardAction:(nullable NSString *)guardAction action:(NSString *)action;` | Add this item to the current runtime collection. | Call during bootstrap/setup before this behavior is exercised. |
| `matchMethod:path:` | `- (nullable ALNRouteMatch *)matchMethod:(NSString *)method path:(NSString *)path;` | Match request method/path against registered routes. | Capture the returned value and propagate errors/validation as needed. |
| `matchMethod:path:format:` | `- (nullable ALNRouteMatch *)matchMethod:(NSString *)method path:(NSString *)path format:(nullable NSString *)format;` | Match request method/path/format against registered routes. | Capture the returned value and propagate errors/validation as needed. |
| `beginRouteGroupWithPrefix:guardAction:formats:` | `- (void)beginRouteGroupWithPrefix:(NSString *)prefix guardAction:(nullable NSString *)guardAction formats:(nullable NSArray *)formats;` | Begin a scoped operation that must be closed by a matching end call. | Call once for a grouped route section, then register routes, then call `endRouteGroup`. |
| `endRouteGroup` | `- (void)endRouteGroup;` | Close a previously started scoped operation. | Always pair with `beginRouteGroupWithPrefix:guardAction:formats:` to avoid leaking group settings. |
| `routeNamed:` | `- (nullable ALNRoute *)routeNamed:(NSString *)name;` | Return one route by registered name. | Capture the returned value and propagate errors/validation as needed. |
| `allRoutes` | `- (NSArray *)allRoutes;` | Return all registered route objects in registration order. | Read this value when you need current runtime/request state. |
| `routeTable` | `- (NSArray *)routeTable;` | Return route metadata table for diagnostics and route inspection. | Read this value when you need current runtime/request state. |
