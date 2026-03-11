# Ops Module

The first-party `ops` module productizes protected operational dashboards,
drilldowns, historical snapshots, and automation-friendly summaries on top of
Arlen's existing health, readiness, metrics, and OpenAPI substrate.

## Install

```bash
./build/arlen module add ops
./build/arlen module doctor --json
./build/arlen module migrate --env development
```

Install `jobs`, `notifications`, `storage`, and `search` as well if you want
the dashboard to surface those module summaries. The module still remains
useful when only a subset of those runtimes is installed.

## Surfaces

HTML routes:

- `GET /ops`
- `GET /ops/modules/:module`

JSON routes:

- `GET /ops/api/summary`
- `GET /ops/api/modules/:module`
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
- recent historical snapshots captured by the ops runtime itself
- contributed cards and widgets from app/module `ALNOpsCardProvider` classes

Status payloads are normalized into:

- `healthy`
- `degraded`
- `failing`
- `informational`

The module remains additive to lower-level endpoints such as `/healthz`,
`/readyz`, `/metrics`, `/clusterz`, and `/openapi.json`.

## Drilldowns and Contributions

- `/ops/modules/:module` and `/ops/api/modules/:module` expose module-specific
  drilldowns for `jobs`, `notifications`, `storage`, and `search`
- apps and modules can contribute dashboard cards and widgets through
  `opsModule.cardProviders.classes`
- malformed provider payloads fail closed instead of partially mutating the
  dashboard response

## Config

Manifest defaults:

- prefix: `/ops`
- API prefix: `/ops/api`
- allowed roles: `operator`, `admin`
- minimum auth assurance level: `2`

Override path and access defaults in app config:

```plist
opsModule = {
  persistence = {
    path = "var/module_state/ops-development.plist";
  };
  cardProviders = {
    classes = ( "MyOpsCardProvider" );
  };
  paths = {
    prefix = "/ops";
    apiPrefix = "api";
  };
  access = {
    roles = ( "operator", "admin" );
    minimumAuthAssuranceLevel = 2;
  };
};
```

## Current Limits

- the dashboard is additive; it does not replace the raw lower-level health,
  metrics, or OpenAPI endpoints
- module drilldowns are still read-only; queue or resource mutations continue
  to happen through module-specific routes such as `/jobs/api/...`
- the module is an operator surface, not a cluster control plane
