# Arlen for Express/NestJS

## Mental Model Mapping

| Express/NestJS | Arlen |
| --- | --- |
| middleware chain | `ALNMiddleware` |
| route handlers/controllers | `ALNController` actions |
| interceptors/guards (Nest) | guard actions + middleware + auth helpers |
| DTO validation pipes | route schema validation + validation helpers |
| module wiring | plugin registration + bootstrap assembly |

## Structure Mapping

- route files/controller modules -> Objective-C controller + route bootstrap
- Nest modules/providers -> plugins + service adapter wiring
- Express app settings -> plist config and startup bootstrapping

## Request/Auth/Data Translation

- Request parsing maps to context/controller param helpers.
- Validation pipes map to route schemas and `validatedParams`.
- JWT guards map to middleware using `ALNAuth` and route role/scope metadata.
- ORM or query-builder usage maps to `ALNPg` and `ALNSQLBuilder`.

## Phased Migration Checklist

1. Mirror middleware order and response headers first.
2. Move one module/bounded context at a time.
3. Keep API envelope and error code mapping stable.
4. Port auth guards/policies before moving sensitive endpoints.
5. Replace queue/cache integrations with Arlen adapters.
6. Retire Node runtime paths only after rollout metrics stabilize.
