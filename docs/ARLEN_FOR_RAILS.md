# Arlen for Rails

## Mental Model Mapping

| Rails | Arlen |
| --- | --- |
| `config/environments/*.rb` | `config/*.plist` + `ALNConfig` |
| Controller actions | `ALNController` actions |
| Rack middleware | `ALNMiddleware` chain |
| `routes.rb` | `registerRouteMethod:...` / `ALNRouter` |
| ActiveSupport notifications | metrics/logging hooks (`ALNMetricsRegistry`, `ALNLogger`) |
| ActiveJob adapters | `ALNJobAdapter` implementations |

## Structure Mapping

- `app/controllers` -> `src/<App>/MVC/Controller`
- `app/views` -> `templates/*.html.eoc`
- `config/initializers` -> app bootstrap/plugin registration
- `db/migrate` -> Arlen SQL migration directory

## Request/Auth/Data Translation

- Before-action filters map to route guards + middleware.
- Strong params map to route schema validation + `validatedParams` accessors.
- `render json:` maps to `renderJSON:error:` or `renderJSONEnvelopeWithData:meta:error:`.
- DB layer migration path:
  - raw SQL + `ALNPg` first
  - `ALNSQLBuilder` where composability is needed

## Phased Migration Checklist

1. Lift existing API contracts first, keep route names stable.
2. Recreate middleware/auth boundaries before migrating controllers.
3. Port high-traffic read paths to Arlen and benchmark with current payloads.
4. Move write paths with explicit transaction tests.
5. Swap background jobs to `ALNJobAdapter` bridge and verify idempotency.
6. Remove Rails compatibility shims after parity CI passes.
