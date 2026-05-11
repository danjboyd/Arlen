# Getting Started: API-First Track

This track optimizes for JSON-first backends with schema/auth contracts and OpenAPI output.

## 1. Create App Skeleton

```bash
/path/to/Arlen/bin/arlen new ApiApp
cd ApiApp
```

## 2. Generate an Endpoint

```bash
/path/to/Arlen/bin/arlen generate endpoint UserList \
  --route /api/users \
  --method GET
```

## 3. Add Contract Metadata

Configure route schema/auth/OpenAPI metadata in your app bootstrap with:

- `configureRouteNamed:requestSchema:responseSchema:summary:operationID:tags:requiredScopes:requiredRoles:includeInOpenAPI:error:`

Use request schemas to validate and coerce incoming params before action logic.

## 4. Start Server and Validate API

```bash
/path/to/Arlen/bin/arlen boomhauer --port 3000
curl -i http://127.0.0.1:3000/api/users
curl -i http://127.0.0.1:3000/openapi.json
curl -i http://127.0.0.1:3000/openapi
```

## 5. Generate TypeScript Contracts For React / SPA Consumers

Export the OpenAPI spec to an app-owned artifact path, then generate the
TypeScript package from ORM descriptors plus that spec:

```bash
curl -s http://127.0.0.1:3000/openapi.json > build/openapi.json
/path/to/Arlen/bin/arlen typescript-codegen \
  --orm-input db/schema/arlen_orm_manifest.json \
  --openapi-input build/openapi.json \
  --output-dir frontend/generated/arlen \
  --manifest db/schema/arlen_typescript.json \
  --target all \
  --force
```

This produces:

- `frontend/generated/arlen/src/models.ts`
- `frontend/generated/arlen/src/validators.ts`
- `frontend/generated/arlen/src/query.ts`
- `frontend/generated/arlen/src/client.ts`
- optional `frontend/generated/arlen/src/react.ts`
- `frontend/generated/arlen/src/meta.ts`

If your OpenAPI export carries top-level `x-arlen.resources`,
`x-arlen.modules`, and `x-arlen.workspace` metadata, Arlen also generates
explicit resource/admin/query/module registries instead of making the frontend
infer them from route names.

See `examples/react_typescript_reference/README.md` for a checked-in React
workspace that consumes the generated package shape.

If you are validating this generated surface inside the Arlen repo itself, the
focused verification entrypoints are:

- `make phase28-ts-generated`
- `make phase28-ts-unit`
- `make phase28-ts-integration`
- `make phase28-react-reference`
- `make phase28-confidence`

## 6. Standardize Error Envelope

For validation failures, use controller helpers:

- `addValidationErrorForField:code:message:`
- `renderValidationErrors`

For success payloads, prefer:

- `renderJSONEnvelopeWithData:meta:error:`

## 7. Add Auth Guardrails

Use `ALNAuth` helpers to:

- parse bearer token
- verify JWT
- apply claims to context
- enforce required scopes/roles

## 8. Production-Ready Checklist

1. Run `make check` and `make ci-quality`.
2. Confirm `/healthz`, `/readyz`, `/metrics` responses.
3. Export OpenAPI spec to artifact path.
4. Regenerate `arlen typescript-codegen` artifacts after contract changes.
5. Document required env/config keys for auth and database.
