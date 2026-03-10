# Ops Module

The first-party `ops` module productizes protected operational dashboards and
automation-friendly summaries on top of Arlen's existing health, readiness,
metrics, and OpenAPI substrate.

## Install

```bash
./build/arlen module add ops
./build/arlen module doctor --json
./build/arlen module migrate --env development
```

Install `jobs`, `notifications`, `storage`, and `search` as well if you want
the dashboard to surface those module summaries.

## Surfaces

HTML routes:

- `GET /ops`

JSON routes:

- `GET /ops/api/summary`
- `GET /ops/api/signals`
- `GET /ops/api/metrics`
- `GET /ops/api/openapi`

The ops JSON routes are included in generated OpenAPI output.

## Protection

The ops module uses the shared operator/admin policy:

- authenticated session
- either `operator` or `admin` role
- AAL2 step-up

That same protection applies to both the HTML dashboard and the JSON routes.

## Summary Model

`ALNOpsModuleRuntime` composes one dashboard payload from:

- `/healthz`, `/readyz`, and `/livez` signal checks
- request/error/latency metrics snapshot data
- jobs queue totals and recent runs
- notifications cards and recent outbox activity
- storage cards, collections, and recent objects
- search status when the search module is installed
- redacted OpenAPI metadata for automation tooling

The module remains additive to lower-level endpoints such as `/healthz`,
`/readyz`, `/metrics`, `/clusterz`, and `/openapi.json`.

## Config

Manifest defaults:

- prefix: `/ops`
- API prefix: `/ops/api`
- allowed roles: `operator`, `admin`
- minimum auth assurance level: `2`

Override path and access defaults in app config:

```plist
opsModule = {
  paths = {
    prefix = "/ops";
    apiPrefix = "/api";
  };
  access = {
    roles = ( "operator", "admin" );
    minimumAuthAssuranceLevel = 2;
  };
};
```

## Current Limits

- the dashboard is summary-oriented; it does not replace the raw lower-level
  health, metrics, or OpenAPI endpoints
- search data only appears when the search module runtime is installed
- module summaries are read-only in this phase; queue mutation still happens
  through the module-specific routes such as `/jobs/api/...`
