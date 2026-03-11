# Search Module

The first-party `search` module productizes searchable-resource registration,
durable index state, job-backed reindexing, public query routes, and shared
admin/ops visibility.

## Install

```bash
./build/arlen module add jobs
./build/arlen module add search
./build/arlen module doctor --json
./build/arlen module migrate --env development
```

Install `admin-ui` as well if you want the module to auto-index admin
resources, contribute the shared `search_indexes` admin resource, and expose
resource drilldown links that line up with the shared admin paths.

## App Registration

Apps register search resources explicitly through Objective-C provider classes.

- `ALNSearchResourceDefinition`: one searchable resource contract
- `ALNSearchResourceProvider`: supplies searchable resources to the runtime
- `ALNSearchEngine`: explicit engine boundary for the shipped in-tree engine or
  future external engines

Configure providers in app config:

```plist
searchModule = {
  engineClass = "ALNDefaultSearchEngine";
  persistence = {
    enabled = YES;
    path = "var/module_state/search-development.plist";
  };
  providers = {
    classes = ( "MyAppSearchProvider" );
  };
  adminUI = {
    autoResources = YES;
    resourceProviderClass = "ALNSearchAdminResourceProvider";
  };
};
```

`ALNSearchModuleRuntime` also supports auto-registration from `admin-ui`
resource metadata when `searchModule.adminUI.autoResources = YES`. Optional
`includeIdentifiers` and `excludeIdentifiers` lists narrow which admin
resources are auto-indexed.

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
- weighted fields and engine-friendly ranking hints where supported

The shipped query contract is fail-closed. Unsupported fields, operators,
sorts, and pagination values are rejected instead of coerced.

The current first-party filter operators are:

- `eq`
- `contains`

The default engine also emits deterministic result snippets/highlights when the
query can be matched against indexed text.

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
- `GET /search/api/resources/:resource`
- `POST /search/api/reindex`
- `POST /search/api/resources/:resource/reindex`

The search JSON routes are included in generated OpenAPI output.

## Protection

- query routes are public by default
- resource drilldown and reindex routes require the shared operator/admin policy:
  - authenticated session
  - either `operator` or `admin` role
  - AAL2 step-up

## Index Lifecycle

- index state is module-owned and can persist to a property-list state file when
  `searchModule.persistence.path` is configured
- full reindex runs build a new generation and then activate it, so active
  queries continue to resolve while rebuild work is in flight
- incremental sync for create/update/delete flows uses the same underlying
  resource contract and generation tracking model
- generation history and reindex history are surfaced in admin and ops payloads

## Jobs, Admin, and Ops Integration

- reindex requests enqueue the system job `search.reindex`
- worker execution rebuilds indexed documents through the same jobs runtime
- the same runtime supports full reindex and incremental sync without custom
  queue glue
- when `admin-ui` is installed, the module can:
  - index app-owned admin resources automatically
  - contribute the shared `search_indexes` admin resource
- the ops module consumes `ALNSearchModuleRuntime` dashboard summaries to show
  indexed-resource counts, generation state, queued reindex jobs, and recent
  failures

## Defaults

Manifest defaults:

- prefix: `/search`
- API prefix: `/search/api`
- allowed roles: `operator`, `admin`
- minimum auth assurance level: `2`
- `engineClass = "ALNDefaultSearchEngine"`
- `adminUI.autoResources = YES`
- `adminUI.resourceProviderClass = "ALNSearchAdminResourceProvider"`

## Current Limits

- the shipped in-tree engine is intentionally simple; vendor-specific external
  engines still need app-owned engine classes
- the current result payload is optimized for deterministic app/admin/operator
  flows rather than full-text relevance experimentation
- admin auto-resource indexing depends on `admin-ui` being configured before the
  search runtime loads
