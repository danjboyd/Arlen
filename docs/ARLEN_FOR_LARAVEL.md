# Arlen for Laravel

## Mental Model Mapping

| Laravel | Arlen |
| --- | --- |
| Service providers | plugins + lifecycle hooks |
| Middleware | `ALNMiddleware` |
| Route groups | `beginRouteGroupWithPrefix:guardAction:formats:` |
| Controllers | `ALNController` |
| Request validation | route schema + validation helpers |
| Jobs/queues | `ALNJobAdapter` and worker runtime |

## Structure Mapping

- `routes/*.php` -> bootstrap route registration
- `app/Http/Controllers` -> Objective-C controller classes
- `resources/views` -> EOC templates
- `config/*.php` -> plist config

## Request/Auth/Data Translation

- Request object access maps to `ALNContext` helpers.
- Policy/gate checks map to auth scopes/roles + guard actions.
- Queue jobs map to `enqueueJobNamed:payload:options:error:` and worker runtime callbacks.
- Eloquent-heavy flows should be migrated with explicit SQL/contract tests.

## Phased Migration Checklist

1. Port middleware order and route groups first.
2. Migrate controllers one bounded context at a time.
3. Keep response envelope shape stable during the cutover window.
4. Port queued job handlers and verify retry/dead-letter behavior.
5. Replace old queue/cache adapters with Arlen adapter equivalents.
6. Remove Laravel compatibility bridge routes in a major release.
