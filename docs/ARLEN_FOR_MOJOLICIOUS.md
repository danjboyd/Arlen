# Arlen for Mojolicious

## Mental Model Mapping

| Mojolicious | Arlen |
| --- | --- |
| `Mojolicious` app | `ALNApplication` |
| routes (`$r->get/post/...`) | `registerRouteMethod:...` / `ALNRouter` |
| controller stash | `stashValue:forKey:` / `stashValues:` |
| helpers/plugins/hooks | plugins + middleware + lifecycle hooks |
| templates (`.ep`) | EOC templates (`.html.eoc`) |
| hypnotoad/runtime config | `boomhauer` for dev, `propane` (with propane accessories) for production process control |

## Structure Mapping

- `lib/MyApp.pm` bootstrap -> Objective-C bootstrap/server entry
- `lib/MyApp/Controller/*.pm` -> Objective-C controller classes
- `templates/*.ep` -> `templates/*.html.eoc`
- Mojolicious config -> plist config

## Request/Auth/Data Translation

- stash usage maps directly to controller stash helpers.
- before_dispatch/after_dispatch hooks map to middleware and lifecycle hooks.
- route conditions/constraints map to route format + guard actions.
- DBI/ORM paths migrate via `ALNPg` + optional `ALNSQLBuilder`.
- websocket/SSE patterns map to built-in realtime helpers:
  - `acceptWebSocketEcho`
  - `acceptWebSocketChannel:`
  - `renderSSEEvents:`

## Phased Migration Checklist

1. Port routing tree and stash-heavy handlers first.
2. Preserve response payloads and template output parity.
3. Move helpers/plugins into Arlen plugins/middleware.
4. Port realtime endpoints (websocket/SSE) with integration tests.
5. Migrate DB access and transaction boundaries with query snapshots.
6. Retire Mojolicious endpoints after parity + soak checks pass.
