# Search Module

The first-party `search` module productizes searchable-resource registration,
safe public result shaping, durable index state, job-backed reindexing, public
query routes, first-party engine adapters, and shared admin/ops visibility.

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

Optional first-party PostgreSQL search uses the same resource/provider
contracts:

```plist
searchModule = {
  engineClass = "ALNPostgresSearchEngine";
  engine = {
    postgres = {
      tableName = "search_module_documents";
      textSearchConfiguration = "simple";
      maxConnections = 2;
    };
  };
};
```

`ALNPostgresSearchEngine` reads
`searchModule.engine.postgres.connectionString` first and falls back to
`database.connectionString`.

Arlen also ships first-party adapters for Meilisearch and
OpenSearch/Elasticsearch:

```plist
searchModule = {
  engineClass = "ALNMeilisearchSearchEngine";
  engine = {
    meilisearch = {
      serviceURL = "http://127.0.0.1:7700";
      apiKey = "change-me";
      indexPrefix = "myapp";
      liveRequestsEnabled = NO;
    };
  };
};
```

```plist
searchModule = {
  engineClass = "ALNOpenSearchSearchEngine";
  engine = {
    opensearch = {
      serviceURL = "http://127.0.0.1:9200";
      apiKey = "change-me";
      indexPrefix = "myapp";
      liveRequestsEnabled = NO;
    };
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
- `summaryField`
- `indexedFields`
- `searchFields`
- `autocompleteFields`
- `suggestionFields`
- `highlightFields`
- `resultFields`
- `facetFields`
- `fieldTypes`
- `filters`
- `sorts`
- `queryModes`
- `queryPolicy`
- `queryRoles`
- `promotions`
- `pathTemplate`
- weighted fields and engine-friendly ranking hints where supported

The shipped query contract is fail-closed. Unsupported fields, operators,
sorts, and pagination values are rejected instead of coerced.

The current first-party filter operators are:

- `eq`
- `contains`
- `gt`
- `gte`
- `lt`
- `lte`
- `in`

Public query routes now return shaped result payloads by default:

- stable top-level result keys such as `resource`, `recordID`, `title`,
  `summary`, `path`, `score`, `generation`, and `highlights`
- a shaped `fields` payload based on `resultFields` or the optional
  `searchModulePublicResultForDocument:metadata:runtime:error:` hook
- no raw `record` dictionary unless an app explicitly returns it from its own
  shaping hook

Resource query policies are explicit:

- `public`
- `authenticated`
- `role_gated`
- `predicate`

The module also reports engine capabilities directly in query/config payloads so
apps can see which engines support highlights, fuzzy matching, autocomplete,
facets, promoted results, cursor pagination, and related behaviors.

## Generator Path

Use the generator when you want an app-owned search resource without reverse
engineering module internals:

```bash
./build/arlen module add jobs
./build/arlen module add search
./build/arlen generate search Catalog
```

That scaffold:

- adds `src/Search/CatalogSearchProvider.{h,m}`
- writes one resource definition plus one provider class
- includes a public-safe `searchModulePublicResultForDocument:` hook
- registers the provider in `config/app.plist`
- adds engine-swap and migration notes under `docs/search/catalog_search.md`

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

Query responses now include richer sections when supported by the selected
engine/resource contract:

- `results`
- `promotedResults`
- `autocomplete`
- `suggestions`
- `facets`
- `pagination`
- `resourceMetadata`
- `engineCapabilities`

They also expose:

- `cursor` metadata when the selected engine supports cursor pagination
- `debug` entries for engine/source/explainability details
- `resourceMetadata.visibility` and `resourceMetadata.syncPolicy` so apps and
  operators can see tenant/soft-delete/sync boundaries explicitly

## Protection

- query routes are public by default
- per-resource `queryPolicy` metadata can require authentication, roles, or an
  app callback/predicate
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
- bulk-import summaries now include `batchSize`, `batchCount`,
  `importedDocuments`, `durationSeconds`, and `throughputPerSecond`
- resources can declare `syncPolicy` and `visibility` rules for:
  - batch sizing and replay limits
  - paused resources and conditional indexing
  - tenant scoping
  - soft-delete and archived-record hiding

## Jobs, Admin, and Ops Integration

- reindex requests enqueue the system job `search.reindex`
- worker execution rebuilds indexed documents through the same jobs runtime
- the same runtime supports full reindex and incremental sync without custom
  queue glue
- when `admin-ui` is installed, the module can:
  - index app-owned admin resources automatically
  - contribute the shared `search_indexes` admin resource
- the ops module consumes `ALNSearchModuleRuntime` dashboard summaries to show
  indexed-resource counts, generation state, queued replay depth, recent
  failures, and recent query history

## Engine Matrix

- `ALNDefaultSearchEngine`: simplest path; substring/fuzzy-style matching,
  facets, suggestions, promotions, and typed filters without extra
  infrastructure.
- `ALNPostgresSearchEngine`: strongest no-extra-service path; PostgreSQL
  FTS/trigram ranking, incremental sync parity, and module-owned document
  storage.
- `ALNMeilisearchSearchEngine`: first-party adapter with engine descriptors,
  fixture-backed contract validation, authoritative live query/sync
  translation, cursor pagination support, and required live confidence
  validation.
- `ALNOpenSearchSearchEngine`: first-party adapter with mappings/aliases
  descriptors, fixture-backed contract validation, authoritative live
  query/sync translation, cursor pagination, and required live confidence
  validation.

## Migration Notes

- Start with the default engine while you are still shaping the public-safe
  result payload and filter/facet contract.
- Move to PostgreSQL when you want a better no-extra-service baseline.
- Move to Meilisearch or OpenSearch when you want external-engine cursor
  pagination, service-owned scaling, or engine-specific explainability.
- Keep the resource contract stable during engine swaps so routes, result
  shaping, and admin/ops drilldowns do not need to change.
- Reindex after every engine change and verify the resource drilldown under
  `/search/api/resources/:resource`.

## Confidence Lane

Phase 27 ships focused search verification and characterization artifacts:

```bash
source tools/source_gnustep_env.sh
make phase27-search-tests
make phase27-search-characterize
make phase27-confidence
```

The artifact pack lands under `build/release_confidence/phase27/` and includes:

- focused search test logs
- runtime-generated query/ranking/facet/suggestion characterization
- required live Meilisearch/OpenSearch query/sync validation manifests
- a machine-readable confidence manifest and summary

A passing `phase27-confidence` run now also requires:

- `ARLEN_PG_TEST_DSN`
- `ARLEN_PHASE27_MEILI_URL`
- `ARLEN_PHASE27_OPENSEARCH_URL`

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

- the shipped default engine is still snapshot-backed and intentionally simpler
  than dedicated search services, even though it now supports typed filters,
  autocomplete, suggestions, facets, promotions, and fuzzy/phrase modes
- PostgreSQL is still the strongest no-extra-service path for search quality
- the Meilisearch and OpenSearch adapters now execute authoritative live
  query/sync flows through the shared Arlen contract, but cluster-native
  analyzer/relevance/ops depth remains lighter than dedicated engine-specific
  frameworks
- admin auto-resource indexing depends on `admin-ui` being configured before the
  search runtime loads
