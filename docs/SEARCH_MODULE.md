# Search Module

The first-party `search` module productizes searchable-resource registration,
job-backed reindexing, public query routes, and shared admin/ops visibility.

## Install

```bash
./build/arlen module add jobs
./build/arlen module add search
./build/arlen module doctor --json
./build/arlen module migrate --env development
```

Install `admin-ui` as well if you want the module to auto-index admin
resources and expose the shared `search_indexes` admin resource.

## App Registration

Apps register search resources explicitly through Objective-C provider classes.

- `ALNSearchResourceDefinition`: one searchable resource contract
- `ALNSearchResourceProvider`: supplies searchable resources to the runtime

Configure providers in app config:

```plist
searchModule = {
  providers = {
    classes = ( "MyAppSearchProvider" );
  };
};
```

`ALNSearchModuleRuntime` also supports auto-registration from `admin-ui`
resource metadata when `searchModule.adminUI.autoResources = YES`.

## Search Contract

Each search resource definition supplies metadata such as:

- `identifier`
- `label`
- `summary`
- `identifierField`
- `primaryField`
- `indexedFields`
- `filters`
- `sorts`
- `pathTemplate`

The current first-party filter operators are:

- `eq`
- `contains`

Unsupported fields, operators, and sorts fail closed.

## Surfaces

HTML routes:

- `GET /search`
- `GET /search/resources/:resource`
- `POST /search/reindex`
- `POST /search/resources/:resource/reindex`

JSON routes:

- `GET /search/api/resources`
- `GET /search/api/query`
- `GET /search/api/resources/:resource/query`
- `POST /search/api/reindex`
- `POST /search/api/resources/:resource/reindex`

The search JSON routes are included in generated OpenAPI output.

## Protection

- query routes are public by default
- reindex routes require the shared operator/admin policy:
  - authenticated session
  - either `operator` or `admin` role
  - AAL2 step-up

## Jobs and Admin Integration

- reindex requests enqueue the system job `search.reindex`
- worker execution rebuilds indexed documents through the same jobs runtime
- when `admin-ui` is installed, the module can:
  - index app-owned admin resources automatically
  - contribute the shared `search_indexes` admin resource
- the ops module consumes `ALNSearchModuleRuntime` dashboard summaries to show
  indexed-resource counts, queued reindex jobs, and dead-letter state

## Defaults

Manifest defaults:

- prefix: `/search`
- API prefix: `/search/api`
- allowed roles: `operator`, `admin`
- minimum auth assurance level: `2`
- `adminUI.autoResources = YES`
- `adminUI.resourceProviderClass = "ALNSearchAdminResourceProvider"`

## Current Limits

- indexed documents are runtime-managed snapshots rather than dedicated search
  tables
- the current first-party result payload exposes titles, summaries, and records,
  but not richer highlight/snippet scoring
- admin auto-resource indexing depends on `admin-ui` being configured before the
  search runtime loads
