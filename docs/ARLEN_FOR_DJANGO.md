# Arlen for Django

## Mental Model Mapping

| Django | Arlen |
| --- | --- |
| `settings.py` | plist config + `ALNConfig` |
| URLconf | `ALNRouter` route registration |
| View function/class | `ALNController` action |
| Middleware stack | `ALNMiddleware` |
| Django forms/serializers validation | route schema + context/controller validation helpers |
| Django signals | lifecycle hooks/plugins/metrics logging paths |

## Structure Mapping

- `project/settings.py` -> `config/app.plist` + env overlays
- `urls.py` -> route registration bootstrap
- `views.py` -> controller classes and action methods
- templates -> `templates/*.html.eoc`

## Request/Auth/Data Translation

- request parsing and helper access:
  - `request.GET`/`request.headers` -> `queryValueForName:` / `headerValueForName:`
- validation:
  - serializer/form required fields -> `requireStringParam:value:` and route schemas
- auth:
  - token/session checks -> middleware + `ALNAuth`
- DB:
  - ORM-heavy paths should move in phases; start with SQL snapshots and contract tests

## Phased Migration Checklist

1. Freeze API response contracts and add Arlen parity tests.
2. Move URL routes and middleware order exactly first.
3. Port stateless JSON views before stateful/form-heavy pages.
4. Move auth and permission checks to middleware + route-required scopes/roles.
5. Replace ORM hotspots with tested SQL queries/builders.
6. Decommission Django endpoints by route group once parity is stable.
