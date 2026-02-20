# API-First Reference App

This example demonstrates an API-first Arlen application with:

- schema contracts
- OpenAPI generation
- auth scope enforcement
- Swagger-style docs UI (`openapi.docsUIStyle = "swagger"`)

All source lives under `examples/api_reference`:

- `examples/api_reference/src/api_reference_server.m`
- `examples/api_reference/config/`

## Run

```bash
make api-reference-server
ARLEN_APP_ROOT=examples/api_reference ./build/api-reference-server --port 3125
```

## Endpoints

- `GET /healthz`
- `GET /api/reference/status`
- `GET /api/reference/users/:id`
  - requires bearer scope `users:read`
- `GET /openapi.json`
- `GET /openapi` (Swagger UI style by default)
- `GET /openapi/viewer`

## Why this exists

Phase 3C requires a concrete API reference app that exercises schema/OpenAPI/auth defaults and can be used by integration/perf checks.
