# Arlen for FastAPI

## Mental Model Mapping

| FastAPI | Arlen |
| --- | --- |
| app + routers | `ALNApplication` + `ALNRouter` |
| dependency injection | middleware/context helpers/plugins |
| Pydantic request/response models | route schema validation + typed contracts |
| OpenAPI auto docs | `openAPISpecification` + `/openapi*` endpoints |
| background tasks | `ALNJobAdapter` |

## Structure Mapping

- `main.py` app bootstrap -> Objective-C app bootstrap
- APIRouter modules -> route registration modules/plugins
- pydantic schemas -> schema dictionaries + typed contract docs/codegen

## Request/Auth/Data Translation

- Path/query/header extraction maps cleanly to `ALNContext` helpers.
- Response models map to envelope + schema response contracts.
- Auth dependencies map to middleware and guard checks.
- Async DB stacks map to adapter-backed calls with explicit transaction boundaries.

## Phased Migration Checklist

1. Export OpenAPI from FastAPI and preserve route/response contracts.
2. Implement equivalent Arlen routes with schema metadata.
3. Validate `/openapi.json` parity for critical endpoints.
4. Move auth dependencies into middleware + route scopes/roles.
5. Migrate background task paths to jobs adapter.
6. Remove FastAPI service once parity, perf, and observability gates pass.
