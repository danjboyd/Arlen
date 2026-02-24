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

## 5. Standardize Error Envelope

For validation failures, use controller helpers:

- `addValidationErrorForField:code:message:`
- `renderValidationErrors`

For success payloads, prefer:

- `renderJSONEnvelopeWithData:meta:error:`

## 6. Add Auth Guardrails

Use `ALNAuth` helpers to:

- parse bearer token
- verify JWT
- apply claims to context
- enforce required scopes/roles

## 7. Production-Ready Checklist

1. Run `make check` and `make ci-quality`.
2. Confirm `/healthz`, `/readyz`, `/metrics` responses.
3. Export OpenAPI spec to artifact path.
4. Document required env/config keys for auth and database.
